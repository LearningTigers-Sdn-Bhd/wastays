# frozen_string_literal: true

require "ostruct"

module Bookings
  class TransitionStatus
    def initialize(booking:, status:, timestamp: nil, user: nil, options: {})
      @booking = booking
      @status = status.to_s
      @timestamp = timestamp || Time.current
      @user = user
      @options = options
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
      business_date = @timestamp.to_date
      is_retroactive = NightAudit.closed_for_date?(@booking.hotel_id, business_date)

      if is_retroactive
        unless @options[:override_night_audit] && @options[:reason].present?
          return failure("The business date #{business_date} is already closed by a night audit. Please provide an override flag and reason for retroactive check-in.")
        end
      end

      folio_number = HotelCounter.increment!(hotel: @booking.hotel, type: "folio")
      guest_reg    = HotelCounter.increment!(hotel: @booking.hotel, type: "guest_registration")

      Booking.transaction do
        @booking.update!(
          status: "checked_in",
          checked_in_at: @timestamp,
          guest_registration_number: guest_reg
        )
        folio = @booking.create_booking_folio!(folio_number: folio_number)

        # Initialize folio with charges and existing payments
        Folios::PostInitialCharges.call(folio: folio, user: @user, options: @options)
        Folios::SyncExistingPayments.call(folio: folio, user: @user, options: @options)
      end

      metadata = {}
      if is_retroactive
        metadata[:retroactive_checkin] = true
        metadata[:retroactive_reason] = @options[:reason]
      end

      Bookings::RecordAuditLog.call(auditable: @booking, user: @user, action_type: "check_in", metadata: metadata)
      Bookings::WebhookTriggerService.new(@booking).trigger(:booking_checked_in)
      Notifications::Dispatcher.new(event: :booking_checked_in, booking: @booking).call
      success
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    def check_out
      Booking.transaction do
        @booking.update!(status: "completed", checked_out_at: @timestamp)
        Bookings::RecordAuditLog.call(auditable: @booking, user: @user, action_type: "check_out")
        mark_assigned_rooms_pending_cleaning
      end

      Bookings::WebhookTriggerService.new(@booking).trigger(:booking_completed)
      Notifications::Dispatcher.new(event: :booking_completed, booking: @booking).call

      success
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    def cancel
      Booking.transaction do
        if @booking.update(status: "cancelled")
          Bookings::RecordAuditLog.call(auditable: @booking, user: @user, action_type: "cancel")
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
