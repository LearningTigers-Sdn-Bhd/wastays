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
      business_date = @booking.check_in.to_date
      is_retroactive = NightAudit.closed_for_date?(@booking.hotel_id, business_date)
      transitioned = false
      error = nil

      Booking.transaction do
        @booking.with_lock do
          @booking.reload

          if @booking.checked_in?
            repair_options = @booking.booking_folio.present? ? @options : @options.reverse_merge(override_night_audit: true)
            Folios::InitializeForBooking.call(booking: @booking, user: @user, options: repair_options, lock: false)
            next
          end

          was_no_show = @booking.status == "no_show"
          unless @booking.status.in?(%w[confirmed no_show])
            error = "Cannot check in booking with status #{@booking.status}"
            next
          end

          if is_retroactive && !(@options[:override_night_audit] && @options[:reason].present?)
            error = "Reason required for backdated check-in on closed date #{business_date}."
            next
          end

          if was_no_show
            unavailable_room = unavailable_assigned_room
            if unavailable_room.present?
              error = "Assigned room #{unavailable_room} is no longer available. Reassign the booking before reinstating this no-show."
              next
            end

            # Re-reserve inventory that was released by the no-show process.
            Bookings::InventoryManager.new(@booking).reserve_by_dates(@booking.check_in.to_date + 1.day, @booking.check_out)
          end

          guest_reg = HotelCounter.increment!(hotel: @booking.hotel, type: "guest_registration")

          @booking.update!(
            status: "checked_in",
            checked_in_at: @timestamp,
            guest_registration_number: guest_reg
          )

          Folios::InitializeForBooking.call(booking: @booking, user: @user, options: @options, lock: false)

          if is_retroactive || was_no_show
            Folios::ProcessCatchUpCharges.call(booking: @booking, user: @user)
          end

          transitioned = true
        end
      end

      return failure(error) if error.present?
      return success unless transitioned

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
      close_result = nil
      error = nil

      Booking.transaction do
        @booking.with_lock do
          @booking.reload

          unless @booking.checked_in?
            error = "Cannot check out booking with status #{@booking.status}"
            next
          end

          close_result = Folios::CloseForCheckout.call(booking: @booking, user: @user, checked_out_at: @timestamp)
          unless close_result.success?
            error = close_result.error
            next
          end

          @booking.update!(status: "completed", checked_out_at: @timestamp)
          Bookings::RecordAuditLog.call(
            auditable: @booking,
            user: @user,
            action_type: "check_out",
            metadata: {
              folio_id: close_result.folio.id,
              folio_number: close_result.folio.folio_number,
              folio_status: close_result.folio.status,
              outstanding_balance: close_result.balance.to_s
            }
          )
          mark_assigned_rooms_pending_cleaning
        end
      end

      return failure(error) if error.present?

      Bookings::WebhookTriggerService.new(@booking).trigger(:booking_completed)
      Notifications::Dispatcher.new(event: :booking_completed, booking: @booking).call

      success
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    def cancel
      transitioned = false
      error = nil

      Booking.transaction do
        @booking.with_lock do
          @booking.reload

          if @booking.status == "cancelled"
            return success
          end

          unless cancellable_status?
            error = "Cannot cancel booking with status #{@booking.status}"
            next
          end

          previous_status = @booking.status
          @booking.update!(status: "cancelled")
          InventoryManager.new(@booking).release if release_inventory_on_cancel?(previous_status)
          Bookings::RecordAuditLog.call(auditable: @booking, user: @user, action_type: "cancel")
          transitioned = true
        end
      end

      return failure(error) if error.present?

      if transitioned
        Bookings::WebhookTriggerService.new(@booking).trigger(:booking_cancelled)
      end

      success
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    def cancellable_status?
      @booking.status.in?(%w[pending confirmed overbooked])
    end

    def release_inventory_on_cancel?(previous_status)
      previous_status.in?(%w[pending confirmed])
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

    def unavailable_assigned_room
      @booking.booking_rooms.includes(:room_type).find do |booking_room|
        next if booking_room.room_number.blank?

        available_rooms = Bookings::AvailableRoomNumbers.new(
          hotel: @booking.hotel,
          room_type: booking_room.room_type,
          check_in: @booking.check_in,
          check_out: @booking.check_out,
          exclude_booking_id: @booking.id
        ).call

        !available_rooms.include?(booking_room.room_number.to_s)
      end&.room_number
    end

    def success
      OpenStruct.new(success?: true, booking: @booking)
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error)
    end
  end
end
