# frozen_string_literal: true


module Folios
  module Lifecycle
    class CloseNoShowFolios
      CLOSE_SOURCE = "no_show_finalization"

      # A folio left open because it still carries a balance, and the balance that
      # kept it open.
      SkippedFolio = Data.define(:folio, :balance)

      # Closing no-show folios is partial by nature: it reports what it closed and
      # what it had to leave, on success and on failure alike.
      Result = ApplicationResult.define(:closed_folios, :skipped_folios)

      def self.call(booking:, user:, business_date:, night_audit: nil)
        new(
          booking: booking,
          user: user,
          business_date: business_date,
          night_audit: night_audit
        ).call
      end

      def initialize(booking:, user:, business_date:, night_audit: nil)
        @booking = booking
        @user = user
        @business_date = business_date.to_date
        @night_audit = night_audit
        @closed_folios = []
        @skipped_folios = []
      end

      def call
        BookingFolio.transaction do
          folios = @booking.booking_folios.includes(:folio_forecasted_charges).to_a
          folios.each(&:lock!)
          folios.each(&:reload)
          balances = fresh_balances(folios)

          folios.each do |folio|
            folio.folio_forecasted_charges.supersede_all!
            next unless folio.open?

            balance = balances.fetch(folio.id, 0.to_d)
            if balance.zero?
              close!(folio)
            else
              @skipped_folios << SkippedFolio.new(folio: folio, balance: balance)
            end
          end
        end

        Result.success(
          closed_folios: @closed_folios,
          skipped_folios: @skipped_folios
        )
      rescue StandardError => e
        Result.failure(
          e.message,
          closed_folios: @closed_folios,
          skipped_folios: @skipped_folios
        )
      end

      private

      def fresh_balances(folios)
        totals = FolioTransaction.where(booking_folio_id: folios.map(&:id))
          .group(:booking_folio_id, :transaction_type)
          .sum(:amount)

        totals.each_with_object(Hash.new(0.to_d)) do |((folio_id, transaction_type), amount), balances|
          multiplier = transaction_type == "payment" ? -1 : 1
          balances[folio_id] += amount.to_d * multiplier
        end
      end

      def close!(folio)
        closed_at = Time.current
        folio.update!(status: "closed", closed_at: closed_at, closed_by: @user)
        FolioOperationLog.create!(
          hotel: folio.hotel,
          booking: @booking,
          actor: @user,
          operation_type: "close_folio",
          source_folio: folio,
          target_folio: folio,
          amount: 0,
          currency: folio.currency,
          reason: "Settled no-show folio closed automatically.",
          metadata: {
            source: CLOSE_SOURCE,
            closed_at: closed_at.iso8601,
            business_date: @business_date.iso8601,
            night_audit_id: @night_audit&.id
          }.compact
        )
        FinancialControls::AuditEventRecorder.call!(
          hotel: folio.hotel,
          business_date: @business_date,
          event_type: "no_show_folio_closed",
          source: CLOSE_SOURCE,
          actor: @user,
          booking_folio: folio,
          booking: @booking,
          night_audit: @night_audit,
          amount: 0,
          currency: folio.currency,
          metadata: {
            closed_at: closed_at.iso8601,
            folio_number: folio.folio_number
          }
        )
        @closed_folios << folio
      end
    end
  end
end
