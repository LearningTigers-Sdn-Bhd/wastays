# frozen_string_literal: true

require "ostruct"

module Rooms
  class StatusResolver
    def initialize(hotel:, room_type:, room_number:, date:, bookings_scope: nil, blocks_scope: nil, statuses_scope: nil)
      @hotel = hotel
      @room_type = room_type
      @room_number = room_number.to_s
      @date = date
      @provided_bookings = bookings_scope
      @provided_blocks = blocks_scope
      @provided_statuses = statuses_scope
    end

    def call
      booking_info = resolve_booking_info

      OpenStruct.new(
        status: physical_status,
        assignable: physical_status == "ready",
        room_status: persisted_status,
        booking_state: booking_info[:state],
        booking_details: booking_info[:details]
      )
    end

    private

    def physical_status
      return "out_of_service" if blocked?

      status = persisted_status&.status || "ready"
      return status if %w[cleaning dirty awaiting_inspection inspection_failed].include?(status)

      return "occupied" if occupied_stay?
      status
    end

    def blocked?
      blocks.any? { |b| b.completed_at.nil? && @date >= b.start_date && @date <= b.end_date }
    end

    def resolve_booking_info
      bks = bookings

      # Filter bookings that cover this date
      # Standard hotel logic: The room is occupied from check_in date up to (but not including) check_out date.
      covering_bks = bks.select { |b| @date >= b.check_in.to_date && @date < b.check_out.to_date }

      # Priority 1: Checked In (Occupied/Red)
      checked_in_bks = covering_bks.select { |b| b.status.in?(%w[checked_in review_due_out checkout_required]) }
      if checked_in_bks.any?
        return { state: :occupied, details: { active: checked_in_bks } }
      end

      # Priority 2: Confirmed (Arriving/Yellow)
      confirmed_bks = covering_bks.select { |b| b.status.in?(%w[confirmed review_no_show]) }
      if confirmed_bks.any?
        return { state: :arrival, details: { active: confirmed_bks } }
      end

      # Priority 3: Completed (Finished/White)
      completed_bks = covering_bks.select { |b| b.status == "completed" }
      if completed_bks.any?
        return { state: :completed, details: { completed: completed_bks } }
      end

      # Default: Available (Green)
      { state: :none, details: { bks: covering_bks } }
    end

    def occupied_stay?
      # We check checked_in status specifically for the "occupied" physical status
      # This is different from the timeline colors which show "stay" for any confirmed booking
      bks = bookings
      bks.any? { |b| b.status.in?(%w[checked_in review_due_out checkout_required]) && b.check_in.to_date <= @date && b.check_out.to_date > @date }
    end

    def bookings
      @bookings ||= begin
        if @provided_bookings
          @provided_bookings
        else
          @hotel.bookings
            .where(status: %w[confirmed review_no_show checked_in review_due_out checkout_required completed])
            .joins(:booking_rooms)
            .where(booking_rooms: { room_type_id: @room_type.id, room_number: @room_number })
            .distinct
        end
      end
    end

    def blocks
      @blocks ||= begin
        if @provided_blocks
          @provided_blocks
        else
          @hotel.room_blocks
            .where(room_type_id: @room_type.id, room_number: @room_number)
        end
      end
    end

    def persisted_status
      @persisted_status ||= if @provided_statuses
        @provided_statuses.first
      else
        @hotel.room_statuses.find_by(room_type_id: @room_type.id, room_number: @room_number)
      end
    end
  end
end
