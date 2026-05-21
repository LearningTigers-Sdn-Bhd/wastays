# frozen_string_literal: true

module FinancialControls
  class EvaluateAnomalies
    def self.call(hotel)
      new(hotel).call
    end

    def initialize(hotel)
      @hotel = hotel
    end

    def call
      {
        unbalanced_folios: unbalanced_folios,
        audit_sync_lags: audit_sync_lags,
        override_abuse: override_abuse,
        summary: {
          hotel_id: @hotel.id,
          hotel_name: @hotel.name,
          evaluated_at: Time.current
        }
      }
    end

    private

    def unbalanced_folios
      # Find closed bookings with non-zero folio balances
      # Note: outstanding_balance is a method, not a column, so we must calculate in Ruby
      # or use a complex SQL join. Ruby is fine for daily background jobs.
      @hotel.bookings.completed
            .joins(:booking_folio)
            .where(booking_folios: { status: "closed" })
            .includes(:booking_folio)
            .to_a
            .select { |b| b.folio_outstanding_balance.to_f.abs > 0.001 }
            .map do |b|
              {
                booking_id: b.id,
                confirmation_token: b.confirmation_token,
                guest_name: b.guest_name,
                balance: b.folio_outstanding_balance.to_f
              }
            end
    end

    def audit_sync_lags
      # Find business dates that are not closed and are more than 2 days old
      threshold_date = 2.days.ago.to_date
      @hotel.hotel_business_dates
            .where.not(status: ["closed", "force_closed"])
            .where("business_date < ?", threshold_date)
            .order(business_date: :asc)
            .map do |bd|
              {
                business_date: bd.business_date,
                status: bd.status,
                lag_days: (Date.current - bd.business_date).to_i
              }
            end
    end

    def override_abuse
      # Count override events in the last 24 hours
      overrides = @hotel.financial_audit_events
                        .where(event_type: "closed_date_override_posted")
                        .where("occurred_at >= ?", 24.hours.ago)
      
      return nil if overrides.count <= 5

      {
        count: overrides.count,
        latest_actors: overrides.order(occurred_at: :desc).limit(5).map { |e| e.actor&.name }.uniq.compact
      }
    end
  end
end
