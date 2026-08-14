# frozen_string_literal: true

module Onboarding
  class ResetOperationalData
    Result = ApplicationResult.define(:hotel)

    INVENTORY_HOLDING_STATUSES = %w[
      confirmed no_show_detected checked_in due_out_detected checkout_required completed
    ].freeze

    def self.call(...) = new(...).call

    def initialize(hotel:, actor:)
      @hotel = hotel
      @actor = actor
    end

    def call
      return Result.success(hotel: @hotel) if reset_already_completed?

      claim = claim_reset
      return claim unless claim.success?
      return Result.success(hotel: @hotel) if reset_already_completed?

      Hotel.transaction do
        @hotel.lock!
        @hotel.reload
        raise ResetAborted, "The training reset is no longer active." unless reset_in_progress?

        reject_irreversible_records!
        delete_operational_data!

        completion = CompleteTraining.call(hotel: @hotel, actor: @actor, decision: "reset")
        raise ResetAborted, completion.error unless completion.success?
      end

      Result.success(hotel: @hotel.reload)
    rescue StandardError => e
      mark_failed(e)
      Rails.error.report(e, handled: true, severity: :error, context: { hotel_id: @hotel.id, operation: "training_reset" })
      Result.failure(e.message, hotel: @hotel)
    end

    private

    ResetAborted = Class.new(StandardError)

    def claim_reset
      error = nil
      done = false

      Hotel.transaction do
        @hotel.lock!
        @hotel.reload
        if @hotel.status == "live" && @hotel.training_data_decision == "reset"
          done = true
          next
        end
        unless @hotel.status == "ready_to_launch" && @hotel.training_data_decision.nil? && @hotel.training_reset_state == "queued"
          error = "The training reset is not queued."
          raise ActiveRecord::Rollback
        end

        @hotel.update!(training_reset_state: "processing")
      end

      return Result.success(hotel: @hotel) if done
      return Result.failure(error, hotel: @hotel) if error

      Result.success(hotel: @hotel)
    end

    def reset_in_progress?
      @hotel.status == "ready_to_launch" &&
        @hotel.training_data_decision.nil? &&
        @hotel.training_reset_state == "processing"
    end

    def reset_already_completed?
      @hotel.reload.status == "live" && @hotel.training_data_decision == "reset"
    end

    # These records should be impossible to create while training. Unlike the demo
    # reset, production reset must never disable database triggers or silently erase
    # externally meaningful settlement/statutory history.
    def reject_irreversible_records!
      blockers = []
      blockers << "issued invoices" if Invoice.where(hotel_id: @hotel.id).exists?
      blockers << "night audits" if NightAudit.where(hotel_id: @hotel.id).exists?
      blockers << "accounts-receivable activity" if accounts_receivable_activity?
      blockers << "channel financial activity" if channel_financial_activity?
      blockers << "gateway payment activity" if gateway_payment_activity?
      blockers << "accounting journal activity" if JournalBatch.where(hotel_id: @hotel.id).exists?
      blockers << "payout activity" if PayoutBatch.where(hotel_id: @hotel.id).exists?
      return if blockers.empty?

      raise ResetAborted, "Start fresh cannot continue because the property has #{blockers.to_sentence}. Keep the current data or contact support."
    end

    def accounts_receivable_activity?
      ArInvoice.where(hotel_id: @hotel.id).exists? ||
        ArPayment.where(hotel_id: @hotel.id).exists? ||
        ArPaymentSubmission.where(hotel_id: @hotel.id).exists? ||
        CorporateArPaymentIntent.where(hotel_id: @hotel.id).exists?
    end

    def channel_financial_activity?
      ChannelSettlement.where(hotel_id: @hotel.id).exists? ||
        OtaFinancialSnapshot.where(hotel_id: @hotel.id).exists?
    end

    def gateway_payment_activity?
      PaymentTransaction.where(booking_id: @hotel.bookings.select(:id))
        .or(PaymentTransaction.where(booking_quote_id: @hotel.booking_quotes.select(:id)))
        .exists?
    end

    def delete_operational_data!
      booking_ids = @hotel.bookings.ids
      quote_ids = @hotel.booking_quotes.ids
      group_ids = @hotel.group_bookings.ids
      folio_ids = BookingFolio.where(booking_id: booking_ids).ids
      transaction_ids = FolioTransaction.where(booking_folio_id: folio_ids).ids
      deposit_ids = Deposit.where(hotel_id: @hotel.id).ids
      guest_ids = BookingGuest.where(booking_id: booking_ids).distinct.pluck(:guest_id) |
        GroupBooking.where(id: group_ids).where.not(organizer_guest_id: nil).pluck(:organizer_guest_id)
      billing_party_ids = BookingBillingParty.where(booking_id: booking_ids).ids

      restore_booking_inventory!
      restore_blocked_inventory!

      delete_audit_and_delivery_records!
      delete_receipts_and_deposits!(deposit_ids)

      FolioForecastedCharge.where(booking_folio_id: folio_ids).delete_all
      FolioRoutingRule.where(booking_id: booking_ids).delete_all
      FolioTransaction.where(id: transaction_ids).delete_all
      BookingFolio.where(id: folio_ids).delete_all
      BookingBillingTerms.where(booking_billing_party_id: billing_party_ids).delete_all
      BookingBillingParty.where(id: billing_party_ids).delete_all

      LegacyBookingSplitLineage.where(legacy_booking_id: booking_ids)
        .or(LegacyBookingSplitLineage.where(child_booking_id: booking_ids)).delete_all
      Booking.where(id: booking_ids).destroy_all
      GroupBillingChangeBatch.where(group_booking_id: group_ids).delete_all
      GroupBooking.where(id: group_ids).destroy_all
      BookingQuote.where(id: quote_ids).destroy_all

      @hotel.room_locks.delete_all
      @hotel.room_blocks.delete_all
      reset_room_statuses!
      delete_orphan_training_guests!(guest_ids)
    end

    def delete_audit_and_delivery_records!
      FinancialAuditEvent.where(hotel_id: @hotel.id).delete_all
      FolioOperationLog.where(hotel_id: @hotel.id).delete_all
      BookingAuditLog.where(hotel_id: @hotel.id).delete_all
      RoomOperationalAuditLog.where(hotel_id: @hotel.id).delete_all
      InventoryAuditLog.where(hotel_id: @hotel.id).delete_all
      NotificationDelivery.where(hotel_id: @hotel.id).delete_all
    end

    def delete_receipts_and_deposits!(deposit_ids)
      Receipt.where(hotel_id: @hotel.id).delete_all
      DepositMovement.where(deposit_id: deposit_ids).delete_all
      Deposit.where(id: deposit_ids).delete_all
      PaymentTransaction.where(booking_id: @hotel.bookings.select(:id)).delete_all
      PaymentTransaction.where(booking_quote_id: @hotel.booking_quotes.select(:id)).delete_all
    end

    def restore_booking_inventory!
      @hotel.bookings.includes(booking_rooms: :room_type).find_each do |booking|
        dates = held_inventory_dates(booking)
        next if dates.empty?

        booking.booking_rooms.each do |booking_room|
          dates.each do |date|
            inventory = booking_room.room_type.room_inventories.lock.find_by(date:)
            inventory&.update!(quantity: inventory.quantity + 1)
          end
        end
      end
    end

    def held_inventory_dates(booking)
      return (booking.check_in.to_date...booking.check_out.to_date).to_a if booking.status.in?(INVENTORY_HOLDING_STATUSES)
      return [] unless booking.status == "no_show"

      last_held_date = booking.no_show_detected_business_date
      return [] unless last_held_date

      (booking.check_in.to_date..[ last_held_date, booking.check_out.to_date - 1.day ].min).to_a
    end

    def restore_blocked_inventory!
      @hotel.room_blocks.where(completed_at: nil).includes(:room_type).find_each do |block|
        (block.start_date..block.end_date).each do |date|
          inventory = block.room_type.room_inventories.lock.find_by(date:)
          next unless inventory

          room_numbers = (inventory.available_room_numbers + [ block.room_number.to_s ]).uniq
          inventory.update!(quantity: inventory.quantity + 1, available_room_numbers: room_numbers)
        end
      end
    end

    def reset_room_statuses!
      @hotel.room_types.includes(:room_statuses).find_each do |room_type|
        expected = room_type.room_numbers.map(&:to_s)
        room_type.room_statuses.where.not(room_number: expected).delete_all
        expected.each do |room_number|
          status = room_type.room_statuses.find_or_initialize_by(hotel: @hotel, room_number:)
          status.assign_attributes(
            status: "ready", assigned_to: nil, last_changed_by: nil,
            last_changed_at: Time.current, dnd: false, dnd_date: nil,
            priority: false, notes: nil
          )
          status.save!
        end
      end
    end

    def delete_orphan_training_guests!(guest_ids)
      Guest.where(id: guest_ids, created_by_hotel_id: @hotel.id).find_each do |guest|
        guest.destroy! unless guest.booking_guests.exists? || guest.prospects.exists?
      end
    end

    def mark_failed(error)
      Hotel.transaction do
        @hotel.lock!
        @hotel.reload
        next unless @hotel.status == "ready_to_launch" && @hotel.training_data_decision.nil?

        @hotel.update!(training_reset_state: "failed")
        @hotel.onboarding_audit_events.create!(
          user: @actor,
          event_type: "training_reset_failed",
          metadata: { error_class: error.class.name, error_message: error.message.to_s.truncate(500) },
          occurred_at: Time.current
        )
      end
    rescue StandardError => reporting_error
      Rails.error.report(reporting_error, handled: true, severity: :error, context: { hotel_id: @hotel.id, operation: "training_reset_failure_recording" })
    end
  end
end
