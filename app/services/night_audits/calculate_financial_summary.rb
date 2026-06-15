# frozen_string_literal: true

module NightAudits
  class CalculateFinancialSummary
    def self.call(hotel:, business_date:)
      new(hotel: hotel, business_date: business_date).call
    end

    def initialize(hotel:, business_date:)
      @hotel = hotel
      @business_date = business_date.to_date
    end

    def call
      # Query FolioTransaction for the business date using posting_date as the source of truth
      transactions = FolioTransaction.joins(booking_folio: :booking)
        .where(bookings: { hotel_id: @hotel.id })
        .where(posting_date: @business_date)

      {
        room_revenue: transactions.where(category: "accommodation").sum(:amount),
        tax_revenue: transactions.where(category: "tax").sum(:amount),
        payments_total: transactions.where(transaction_type: "payment").where("amount > 0").sum(:amount),
        refunds_total: transactions.where(transaction_type: "payment").where("amount < 0").sum(:amount).abs,
        no_show_charges: transactions.where(category: "no_show_charge").sum(:amount),
        adjustments_total: transactions.where(category: [ "adjustment", "discount", "correction", "write_off" ]).sum(:amount)
      }
    end
  end
end
