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
        if @booking.status == "review_due_out"
          simple_transition("checked_in", @options[:event] || "resolve_late_checkout")
        else
          check_in
        end
      when "completed"
        check_out
      when "cancelled"
        cancel
      when "review_due_out"
        simple_transition("review_due_out", @options[:event] || "detect_late_checkout")
      else
        failure("Unsupported status transition: #{@status}")
      end
    rescue StandardError => e
      failure(e.message)
    end

    private

    def simple_transition(new_status, event)
      Booking.transaction do
        @booking.with_lock do
          @booking.reload
          @booking.transition_status_to!(new_status, event: event)
          Bookings::RecordAuditLog.call(
            auditable: @booking,
            user: @user,
            action_type: "status_change",
            metadata: { from: @booking.status_was, to: new_status, event: event, reason: @options[:reason] }
          )
        end
      end
      success
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    def check_in
      business_date = @booking.check_in.to_date
      is_retroactive = @booking.hotel.date_closed?(business_date, @timestamp)
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

          guest_reg = @booking.guest_registration_number || HotelCounter.increment!(hotel: @booking.hotel, type: "guest_registration")

          # Sync room number to hotel_snapshot for consistency
          room_number = @booking.booking_rooms.first&.room_number
          if room_number.present?
            @booking.hotel_snapshot ||= {}
            @booking.hotel_snapshot = @booking.hotel_snapshot.merge("room_number" => room_number)
          end

          @booking.transition_status_to!(
            "checked_in",
            event: was_no_show ? "reinstate" : "check_in",
            attributes: {
              checked_in_at: @timestamp,
              guest_registration_number: guest_reg
            }
          )

          Folios::InitializeForBooking.call(booking: @booking, user: @user, options: @options, lock: false)

          deposit_result = record_security_deposit_if_requested
          unless deposit_result.success?
            error = deposit_result.error
            raise ActiveRecord::Rollback
          end
          @security_deposit = deposit_result.deposit

          if is_retroactive || was_no_show
            Folios::ProcessCatchUpCharges.call(booking: @booking, user: @user, is_reinstate: was_no_show)
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
      if @security_deposit.present?
        metadata[:security_deposit_id] = @security_deposit.id
        metadata[:security_deposit_amount] = @security_deposit.amount.to_d.to_s("F")
      end

      Bookings::RecordAuditLog.call(auditable: @booking, user: @user, action_type: "check_in", metadata: metadata)
      Bookings::WebhookTriggerService.new(@booking).trigger(:booking_checked_in)
      Notifications::Dispatcher.new(event: :booking_checked_in, booking: @booking).call
      success
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    def record_security_deposit_if_requested
      deposit_options = @options[:security_deposit]
      return OpenStruct.new(success?: true) if deposit_options.blank?

      Deposits::RecordSecurityDeposit.call(
        booking: @booking,
        folio: @booking.booking_folio,
        user: @user,
        amount: deposit_options[:amount],
        payment_method: deposit_options[:payment_method],
        external_reference: deposit_options[:external_reference]
      )
    end

    def check_out
      close_result = nil
      error = nil

      Booking.transaction do
        @booking.with_lock do
          @booking.reload

          unless @booking.checked_in? || @booking.status == "review_due_out"
            error = "Cannot check out booking with status #{@booking.status}"
            next
          end

          close_result = Folios::CloseForCheckout.call(booking: @booking, user: @user, checked_out_at: @timestamp)
          unless close_result.success?
            error = close_result.error
            next
          end

          @booking.transition_status_to!("completed", event: "check_out", attributes: { checked_out_at: @timestamp })
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
          mark_assigned_rooms_dirty
        end
      end

      return failure(error) if error.present?

      unless @options[:defer_side_effects]
        Bookings::WebhookTriggerService.new(@booking).trigger(:booking_completed)
        Notifications::Dispatcher.new(event: :booking_completed, booking: @booking).call
        SendInvoiceEmailJob.perform_later(@booking.id)
      end

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
          @booking.transition_status_to!("cancelled", event: "cancel")
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

    def mark_assigned_rooms_dirty
      @booking.booking_rooms.includes(:room_type).where.not(room_number: [ nil, "" ]).find_each do |booking_room|
        room_status = RoomStatus.find_or_create_by!(
          hotel: @booking.hotel,
          room_type: booking_room.room_type,
          room_number: booking_room.room_number
        )

        Rooms::SetStatus.new(
          room_status: room_status,
          status: "dirty",
          user: @user,
          booking: @booking,
          event_type: "checkout_marked_dirty",
          reason: nil,
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
