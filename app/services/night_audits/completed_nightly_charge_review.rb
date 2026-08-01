# frozen_string_literal: true

module NightAudits
  class CompletedNightlyChargeReview
    Entry = Data.define(:booking, :reconciliation, :issues, :expected_total)

    def self.call(night_audit:)
      new(night_audit: night_audit).call
    end

    def initialize(night_audit:)
      @night_audit = night_audit
      @hotel = night_audit.hotel
      @business_date = night_audit.business_date.to_date
    end

    def call
      return [] unless @night_audit.completed?

      candidates.filter_map do |booking|
        next if booking.booking_folio.blank?

        reconciliation = Folios::Charges::NightlyChargeReconciliation.call(
          booking: booking,
          business_date: @business_date,
          allow_closed_folio: true
        )
        next if reconciliation.valid?

        Entry.new(
          booking: booking,
          reconciliation: reconciliation,
          issues: reconciliation.issues,
          expected_total: reconciliation.entries.sum do |entry|
            entry[:issues].empty? ? 0.to_d : entry[:line][:amount].to_d
          end
        )
      end
    end

    private

    def candidates
      @hotel.bookings
        .where(status: %w[checked_in due_out_detected checkout_required completed])
        .occupying_night_on(@business_date, @hotel.hotel_time_zone)
        .includes(:booking_rooms, booking_folios: [ :folio_transactions, :folio_forecasted_charges ])
        .order(:id)
        .to_a
    end
  end
end
