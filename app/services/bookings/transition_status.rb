# frozen_string_literal: true

require "ostruct"

module Bookings
  class TransitionStatus
    def initialize(booking:, status:, timestamp: nil, user: nil)
      @booking = booking
      @status = status.to_s
      @timestamp = timestamp || Time.current
      @user = user
    end

    def call
      case @status
      when "checked_in"
        check_in
      when "completed"
        check_out
      when "cancelled"
        cancel
      else
        failure("Unsupported status transition: #{@status}")
      end
    rescue StandardError => e
      failure(e.message)
    end

    private

    def check_in
      if @booking.update(status: "checked_in", checked_in_at: @timestamp)
        Bookings::WebhookTriggerService.new(@booking).trigger(:booking_checked_in)
        success
      else
        failure(@booking.errors.full_messages.to_sentence)
      end
    end

    def check_out
      Booking.transaction do
        @booking.update!(status: "completed", checked_out_at: @timestamp)
        mark_assigned_rooms_pending_cleaning
      end

      Bookings::WebhookTriggerService.new(@booking).trigger(:booking_completed)

      success
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    def cancel
      Booking.transaction do
        if @booking.update(status: "cancelled")
          InventoryManager.new(@booking).release
          Bookings::WebhookTriggerService.new(@booking).trigger(:booking_cancelled)
          success
        else
          failure(@booking.errors.full_messages.to_sentence)
        end
      end
    end

    def mark_assigned_rooms_pending_cleaning
      @booking.booking_rooms.includes(:room_type).where.not(room_number: [ nil, "" ]).find_each do |booking_room|
        room_status = RoomStatus.find_or_create_by!(
          hotel: @booking.hotel,
          room_type: booking_room.room_type,
          room_number: booking_room.room_number
        )

        Rooms::SetStatus.new(
          room_status: room_status,
          status: "pending_cleaning",
          user: @user,
          booking: @booking,
          event_type: "checkout_marked_pending_cleaning",
          reason: "Guest checked out",
          metadata: { "booking_id" => @booking.id }
        ).call
      end
    end

    def success
      OpenStruct.new(success?: true, booking: @booking)
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error)
    end
  end
end
