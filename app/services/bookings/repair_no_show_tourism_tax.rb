# frozen_string_literal: true

require "ostruct"

module Bookings
  class RepairNoShowTourismTax
    include Authorizable

    SOURCE = "no_show_tourism_tax_repair"
    REASON = "no_show_tourism_tax_not_due"
    NOTE = "Tourism tax removed because the guest did not check in."
    REQUIRED_PERMISSIONS = %w[manage_bookings post_folio_corrections].freeze

    def self.call(booking:, user:)
      new(booking: booking, user: user).call
    end

    def self.eligible_charges_for(booking)
      corrected_ids = booking.booking_folios
        .joins(:folio_transactions)
        .merge(FolioTransaction.adjustment)
        .where.not("folio_transactions.metadata->>'reversed_transaction_id' IS NULL")
        .pluck(Arel.sql("folio_transactions.metadata->>'reversed_transaction_id'"))
        .map(&:to_i)

      FolioTransaction
        .joins(:booking_folio)
        .where(booking_folios: { booking_id: booking.id })
        .charge
        .where(category: "tax", voided_by_transaction_id: nil)
        .where("folio_transactions.metadata->>'posting_source' = ?", "no_show")
        .where.not(id: corrected_ids)
        .includes(:booking_folio)
        .select do |transaction|
          Booking.tourism_tax_line?(transaction.metadata.to_h["tax_line"])
        end
    end

    def self.needed?(booking)
      booking.status == "no_show" && eligible_charges_for(booking).any?
    end

    def initialize(booking:, user:)
      @booking = booking
      @user = user
      @reversal_transactions = []
    end

    def call
      return failure("Only no-show bookings can have tourism tax repaired.") unless @booking.status == "no_show"
      return failure("You do not have permission to repair this no-show folio.") unless permitted?

      NightAudits::OperationalChangeGuard.call!(hotel: @booking.hotel, action: :repair_no_show_folio)

      close_result = nil
      Booking.transaction do
        @booking.with_lock do
          @booking.reload
          raise "Only no-show bookings can have tourism tax repaired." unless @booking.status == "no_show"

          charges = self.class.eligible_charges_for(@booking)
          return success_without_changes if charges.empty?

          charges.group_by(&:booking_folio).each do |folio, folio_charges|
            reopen_for_repair!(folio) if folio.closed?
            folio_charges.each { |charge| reverse!(charge) }
          end

          close_result = Folios::CloseNoShowFolios.call(
            booking: @booking,
            user: @user,
            business_date: @booking.hotel.current_business_date
          )
          raise close_result.error unless close_result.success?
        end
      end

      OpenStruct.new(
        success?: true,
        booking: @booking,
        reversal_transactions: @reversal_transactions,
        repaired_amount: @reversal_transactions.sum { |transaction| -transaction.amount.to_d },
        closed_folios: close_result.closed_folios,
        skipped_folios: close_result.skipped_folios
      )
    rescue StandardError => e
      failure(e.message)
    end

    private

    def permitted?
      actor_permits_all?(@user, REQUIRED_PERMISSIONS, hotel: @booking.hotel)
    end

    def reopen_for_repair!(folio)
      folio.reopening_for_correction do
        folio.update!(status: "open", closed_at: nil, closed_by: nil)
        FolioOperationLog.create!(
          hotel: folio.hotel,
          booking: @booking,
          actor: @user,
          operation_type: "reopen_folio",
          source_folio: folio,
          target_folio: folio,
          currency: folio.currency,
          reason: NOTE,
          metadata: { source: SOURCE, reopened_at: Time.current.iso8601 }
        )
      end
    end

    def reverse!(charge)
      result = Folios::InsertTransaction.new(
        booking_folio: charge.booking_folio,
        amount: -charge.amount,
        transaction_type: :adjustment,
        category: :correction,
        user: @user,
        description: "Void no-show tourism tax: #{charge.description}",
        posting_date: @booking.hotel.current_business_date,
        options: {
          posting_source: SOURCE,
          reversal_of_transaction: charge,
          correction_reason: REASON,
          correction_note: NOTE,
          metadata: {
            source: SOURCE,
            reversed_transaction_id: charge.id,
            booking_id: @booking.id,
            tourism_tax: true
          }
        }
      ).call
      raise "Failed to reverse no-show tourism tax: #{result.error}" unless result.success?

      charge.update!(voided_by_transaction: result.transaction)
      record_repair_event!(charge, result.transaction)
      @reversal_transactions << result.transaction
    end

    def record_repair_event!(charge, reversal)
      FinancialControls::AuditEventRecorder.call!(
        hotel: @booking.hotel,
        business_date: @booking.hotel.current_business_date,
        event_type: "no_show_tourism_tax_repaired",
        source: SOURCE,
        actor: @user,
        booking_folio: charge.booking_folio,
        booking: @booking,
        folio_transaction: reversal,
        amount: charge.amount,
        currency: charge.currency,
        reason: REASON,
        metadata: {
          original_transaction_id: charge.id,
          reversal_transaction_id: reversal.id,
          correction_note: NOTE
        }
      )
    end

    def failure(error)
      OpenStruct.new(
        success?: false,
        error: error,
        booking: @booking,
        reversal_transactions: @reversal_transactions,
        repaired_amount: 0.to_d,
        closed_folios: [],
        skipped_folios: []
      )
    end

    def success_without_changes
      OpenStruct.new(
        success?: true,
        booking: @booking,
        reversal_transactions: [],
        repaired_amount: 0.to_d,
        closed_folios: [],
        skipped_folios: []
      )
    end
  end
end
