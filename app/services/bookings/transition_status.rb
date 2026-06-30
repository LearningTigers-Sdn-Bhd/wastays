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
      NightAudits::OperationalChangeGuard.call!(
        hotel: @booking.hotel,
        action: "transition_status:#{@status}",
        night_audit: @options[:night_audit]
      )

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
      when "checkout_required"
        simple_transition("checkout_required", @options[:event] || "reject_late_checkout")
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
          @booking.transition_status_to!(new_status, event: event, attributes: @options[:attributes] || {})
          Bookings::RecordAuditLog.call!(
            auditable: @booking,
            user: @user,
            action_type: "status_change",
            source: @options[:source],
            old_value: { "status" => @booking.status_before_last_save },
            new_value: { "status" => new_status },
            reason: @options[:reason],
            metadata: { from: @booking.status_before_last_save, to: new_status, event: event }.merge(@options[:metadata] || {})
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

            if @options[:attributes].present?
              @booking.update!(@options[:attributes])
              sync_room_number_to_snapshot
            end
            tourism_tax_result = record_tourism_tax_payment_if_requested
            unless tourism_tax_result.success?
              error = tourism_tax_result.error
              raise ActiveRecord::Rollback
            end
            next
          end

          was_review_no_show = @booking.status == "review_no_show"
          unless @booking.status.in?(%w[confirmed review_no_show])
            error = "Cannot check in booking with status #{@booking.status}"
            next
          end

          if is_retroactive && !(@options[:override_night_audit] && @options[:reason].present?)
            error = "Reason required for backdated check-in on closed date #{business_date}."
            next
          end

          guest_reg = @booking.guest_registration_number || HotelCounter.increment!(hotel: @booking.hotel, type: "guest_registration")

          sync_room_number_to_snapshot

          @booking.booking_rooms.includes(:room_type).where.not(room_number: [ nil, "" ]).find_each do |booking_room|
            room_status = RoomStatus.find_by(
              hotel: @booking.hotel,
              room_type: booking_room.room_type,
              room_number: booking_room.room_number
            )
            room_status&.update!(dnd: false, dnd_date: nil)
          end

          attributes = (@options[:attributes] || {}).merge(
            checked_in_at: @timestamp,
            guest_registration_number: guest_reg
          )

          @booking.transition_status_to!(
            "checked_in",
            event: was_review_no_show ? "backdated_check_in" : "check_in",
            attributes: attributes
          )

          Folios::InitializeForBooking.call(booking: @booking, user: @user, options: @options, lock: false)

          tourism_tax_result = record_tourism_tax_payment_if_requested
          unless tourism_tax_result.success?
            error = tourism_tax_result.error
            raise ActiveRecord::Rollback
          end

          deposit_result = record_security_deposit_if_requested
          unless deposit_result.success?
            error = deposit_result.error
            raise ActiveRecord::Rollback
          end
          @security_deposit = deposit_result.deposit

          if @security_deposit.present?
            @booking.update!(deposit_status: "held")
          end

          if is_retroactive || was_review_no_show
            Folios::ProcessCatchUpCharges.call(
              booking: @booking,
              user: @user,
              is_reinstate: false,
              reason: @options[:reason]
            )
          end

          Bookings::RecordAuditLog.call!(
            auditable: @booking,
            user: @user,
            action_type: "check_in",
            source: @options[:source],
            old_value: { "status" => was_review_no_show ? "review_no_show" : "confirmed" },
            new_value: { "status" => "checked_in", "checked_in_at" => @booking.checked_in_at },
            reason: @options[:reason],
            metadata: check_in_audit_metadata(is_retroactive).merge("room_number" => @booking.booking_rooms.first&.room_number)
          )
          transitioned = true
        end
      end

      return failure(error) if error.present?
      return success unless transitioned

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

    def record_tourism_tax_payment_if_requested
      return OpenStruct.new(success?: true) unless @booking.tourism_tax_collected?

      Folios::RecordTourismTaxPayment.call(
        booking: @booking,
        user: @user,
        options: @options.except(:attributes, :security_deposit)
      )
    end

    def check_in_audit_metadata(is_retroactive)
      metadata = {}
      if is_retroactive
        metadata[:retroactive_checkin] = true
        metadata[:retroactive_reason] = @options[:reason]
        metadata[:backdate_reason_category] = @options[:backdate_reason_category]
        metadata[:backdate_reason_details] = @options[:backdate_reason_details]
      end
      if @security_deposit.present?
        metadata[:security_deposit_id] = @security_deposit.id
        metadata[:security_deposit_amount] = @security_deposit.amount.to_d.to_s("F")
      end
      metadata
    end

    def check_out
      close_result = nil
      error = nil

      Booking.transaction do
        @booking.with_lock do
          @booking.reload

          unless @booking.checked_in? || @booking.status == "checkout_required"
            error = "Cannot check out booking with status #{@booking.status}"
            next
          end

          close_result = Folios::CloseForCheckout.call(booking: @booking, user: @user, checked_out_at: @timestamp, options: @options)
          unless close_result.success?
            error = close_result.error
            next
          end

          deposit_release_result = release_security_deposit_if_requested
          unless deposit_release_result.success?
            error = deposit_release_result.error
            next
          end
          @security_deposit_release = deposit_release_result

          @booking.transition_status_to!(
            "completed",
            event: "check_out",
            attributes: (@options[:attributes] || {}).merge(checked_out_at: @timestamp)
          )
          Bookings::RecordAuditLog.call!(
            auditable: @booking,
            user: @user,
            action_type: "check_out",
            source: @options[:source],
            old_value: { "status" => @booking.status_before_last_save },
            new_value: { "status" => "completed", "checked_out_at" => @booking.checked_out_at },
            metadata: checkout_audit_metadata(close_result)
          )
          mark_assigned_rooms_dirty
        end

        raise ActiveRecord::Rollback if error.present?
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

    def release_security_deposit_if_requested
      release_options = @options[:security_deposit_release]
      return OpenStruct.new(success?: true, deposit_ids: [], total: 0.to_d) if release_options.blank?

      Deposits::ReleaseHeldDeposits.call(
        booking: @booking,
        user: @user,
        released_at: @timestamp,
        method: release_options[:method],
        reference: release_options[:reference]
      )
    end

    def checkout_audit_metadata(close_result)
      metadata = {
        folio_id: close_result.folio.id,
        folio_number: close_result.folio.folio_number,
        folio_status: close_result.folio.status,
        outstanding_balance: close_result.balance.to_s
      }

      if @security_deposit_release&.deposit_ids&.any?
        metadata[:security_deposit_release] = {
          deposit_ids: @security_deposit_release.deposit_ids,
          total: @security_deposit_release.total.to_d.to_s("F"),
          method: @security_deposit_release.method,
          reference: @security_deposit_release.reference,
          released_at: @security_deposit_release.released_at.iso8601
        }
      end

      metadata
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
          @booking.transition_status_to!("cancelled", event: "cancel", attributes: @options[:attributes] || {})
          InventoryManager.new(@booking).release if release_inventory_on_cancel?(previous_status)
          release_review_rooms_to_ready if previous_status == "review_no_show"
          Bookings::RecordAuditLog.call!(
            auditable: @booking,
            user: @user,
            action_type: "cancel",
            source: @options[:source],
            old_value: { "status" => previous_status },
            new_value: { "status" => "cancelled" },
            reason: @options[:reason]
          )
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
      @booking.status.in?(%w[pending confirmed review_no_show overbooked])
    end

    def release_inventory_on_cancel?(previous_status)
      previous_status.in?(%w[pending confirmed review_no_show])
    end

    def mark_assigned_rooms_dirty
      @booking.booking_rooms.includes(:room_type).where.not(room_number: [ nil, "" ]).find_each do |booking_room|
        room_status = RoomStatus.find_or_create_by!(
          hotel: @booking.hotel,
          room_type: booking_room.room_type,
          room_number: booking_room.room_number
        )

        room_status.update!(dnd: false, dnd_date: nil)

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

    def release_review_rooms_to_ready
      result = Bookings::ReleaseAssignedRooms.call(
        booking: @booking,
        user: @user,
        event_type: "review_no_show_cancelled",
        reason: @options[:reason],
        metadata: { "source" => "bookings_transition_status" }
      )
      raise result.error unless result.success?
    end

    def sync_room_number_to_snapshot
      room_number = @booking.booking_rooms.first&.room_number
      if room_number.present?
        @booking.hotel_snapshot ||= {}
        @booking.hotel_snapshot = @booking.hotel_snapshot.merge("room_number" => room_number)
        @booking.update_columns(hotel_snapshot: @booking.hotel_snapshot) if @booking.persisted?
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
