module Folios
  class GenerateForecastedCharges
    include NightlyChargeCalculation

    def self.call(booking_folio:)
      new(booking_folio:).call
    end

    def initialize(booking_folio:)
      @booking_folio = booking_folio
    end

    def call
      booking = @booking_folio.booking
      nights = (booking.check_in.to_date...booking.check_out.to_date).to_a

      nights.each do |date|
        forecast_accommodation(date, booking)
        forecast_taxes(date, booking)
      end
    end

    private

    def forecast_accommodation(date, booking)
      booking.booking_rooms.each do |room|
        amount = nightly_room_amount(room, date)
        next if amount.zero?

        @booking_folio.folio_forecasted_charges.create!(
          stay_date: date,
          charge_kind: "accommodation",
          identity: room.id.to_s,
          amount: amount,
          description: "Room Charge - #{date}"
        )
      end
    end

    def forecast_taxes(date, booking)
      tax_postings_for(booking, date).each_with_index do |tax_line, index|
        amount = tax_line_amount(tax_line)
        next if amount.zero?

        @booking_folio.folio_forecasted_charges.create!(
          stay_date: date,
          charge_kind: "tax",
          identity: tax_line_identity(tax_line, index),
          amount: amount,
          description: "Tax: #{tax_line_name(tax_line)} - #{date}"
        )
      end
    end
  end
end
