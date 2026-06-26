module Folios
  class GenerateForecastedCharges
    def self.call(booking_folio:)
      new(booking_folio:).call
    end

    def initialize(booking_folio:)
      @booking_folio = booking_folio
    end

    def call
      Folios::SyncForecastedCharges.call(booking_folio: @booking_folio)
    end
  end
end
