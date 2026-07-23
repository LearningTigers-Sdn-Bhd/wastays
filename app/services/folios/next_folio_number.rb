# frozen_string_literal: true

module Folios
  # Single source of folio numbers. Wraps the hotel folio counter but floors it
  # at the hotel's current max folio_number, so a counter that has drifted behind
  # bulk-loaded folios (snapshot / seed / demo reseed) can never reissue a number
  # that already exists. Self-heals: the first call past a stale counter advances
  # it past the max, and subsequent calls run straight off the counter again.
  class NextFolioNumber
    def self.call(hotel:)
      floor = BookingFolio.where(hotel_id: hotel.id).maximum(:folio_number)
      HotelCounter.increment!(hotel: hotel, type: "folio", floor: floor)
    end
  end
end
