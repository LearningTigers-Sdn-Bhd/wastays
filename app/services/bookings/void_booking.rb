# frozen_string_literal: true

require "ostruct"

module Bookings
  class VoidBooking
    PRE_ARRIVAL_STATUSES = %w[pending confirmed no_show_detected].freeze
    IN_HOUSE_STATUSES = %w[checked_in due_out_detected checkout_required].freeze

    def self.call(booking:, user:, reason:, timestamp: Time.current)
      new(booking:, user:, reason:, timestamp:).call
    end

    def initialize(booking:, user:, reason:, timestamp: Time.current)
      @booking = booking
      @user = user
      @reason = reason.to_s.strip
      @timestamp = timestamp
    end

    def call
      return failure("Void reason is required.") if @reason.blank?

      NightAudits::OperationalChangeGuard.call!(hotel: @booking.hotel, action: "void_booking")

      Booking.transaction do
        @booking.with_lock do
          @booking.reload
          return success if @booking.status == "voided"

          previous_status = @booking.status
          @booking.transition_status_to!("voided", event: "void")
          release_inventory(previous_status)
          end_in_house_occupancy if previous_status.in?(IN_HOUSE_STATUSES)
          record_audit(previous_status)
        end
      end

      success
    rescue StandardError => e
      failure(e.message)
    end

    private

    def release_inventory(previous_status)
      manager = InventoryManager.new(@booking)
      return manager.release if previous_status.in?(PRE_ARRIVAL_STATUSES)
      return unless previous_status.in?(IN_HOUSE_STATUSES)

      business_date = @booking.hotel.current_business_date || @booking.hotel.business_date_for(@timestamp)
      manager.release_by_dates(business_date, @booking.check_out.to_date) if business_date < @booking.check_out.to_date
    end

    def end_in_house_occupancy
      @booking.booking_rooms.includes(:room_type).where.not(room_number: [ nil, "" ]).find_each do |booking_room|
        room_status = RoomStatus.create_with(status: "ready").find_or_create_by!(
          hotel: @booking.hotel,
          room_type: booking_room.room_type,
          room_number: booking_room.room_number
        )
        room_status.update!(dnd: false, dnd_date: nil)

        result = Rooms::SetStatus.new(
          room_status:,
          status: "dirty",
          user: @user,
          booking: @booking,
          event_type: "void_booking_marked_dirty",
          reason: @reason,
          metadata: { "booking_id" => @booking.id }
        ).call
        raise result.error unless result.success?
      end
    end

    def record_audit(previous_status)
      Bookings::RecordAuditLog.call!(
        auditable: @booking,
        user: @user,
        action_type: "void",
        old_value: { "status" => previous_status },
        new_value: { "status" => "voided" },
        reason: @reason,
        metadata: { "previous_status" => previous_status, "folios_unchanged" => true }
      )
    end

    def success
      OpenStruct.new(success?: true, booking: @booking)
    end

    def failure(error)
      OpenStruct.new(success?: false, error:, booking: @booking)
    end
  end
end
