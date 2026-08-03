# frozen_string_literal: true

module NightAudits
  class NightlyChargeCandidates
    def self.call(hotel:, business_date:)
      hotel.bookings
        .includes(:booking_rooms, booking_folios: :folio_transactions)
        .checked_in
        .occupying_night_on(business_date.to_date, hotel.hotel_time_zone)
    end
  end
end
