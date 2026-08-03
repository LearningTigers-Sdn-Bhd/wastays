# frozen_string_literal: true

module NightAudits
  class TransactionsForBusinessDate
    def self.call(hotel:, business_date:)
      FolioTransaction
        .joins(booking_folio: :booking)
        .where(bookings: { hotel_id: hotel.id })
        .where(posting_date: business_date.to_date)
    end
  end
end
