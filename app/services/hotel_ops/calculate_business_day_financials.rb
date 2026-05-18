# frozen_string_literal: true

module HotelOps
  class CalculateBusinessDayFinancials
    def self.call(hotel:, business_date:)
      new(hotel: hotel, business_date: business_date).call
    end

    def initialize(hotel:, business_date:)
      @hotel = hotel
      @business_date = business_date.to_date
    end

    def call
      window = @hotel.business_day_window_for(@business_date)

      # Query FolioTransaction for the business date
      transactions = FolioTransaction.joins(booking_folio: :booking)
        .where(bookings: { hotel_id: @hotel.id })
        .where("metadata->>'stay_date' = ? OR (transaction_type = 'payment' AND folio_transactions.created_at >= ? AND folio_transactions.created_at < ?)",
               @business_date.iso8601, window.begin, window.end)

      # Identify no-shows via metadata or category
      no_show_penalties_query = transactions.where("metadata->>'posting_source' = ? OR category = ?", "no_show", "no_show_penalty")
      no_show_ids = no_show_penalties_query.select(:id)

      {
        room_revenue: transactions.where(category: "accommodation").where.not(id: no_show_ids).sum(:amount),
        tax_revenue: transactions.where(category: "tax").where.not(id: no_show_ids).sum(:amount),
        payments_total: transactions.where(transaction_type: "payment").where("amount > 0").sum(:amount),
        refunds_total: transactions.where(transaction_type: "payment").where("amount < 0").sum(:amount).abs,
        no_show_penalties: no_show_penalties_query.sum(:amount)
      }
    end
  end
end
