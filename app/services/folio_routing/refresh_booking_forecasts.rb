# frozen_string_literal: true

module FolioRouting
  class RefreshBookingForecasts
    def self.call(booking:)
      new(booking:).call
    end

    def initialize(booking:)
      @booking = booking
    end

    def call
      snapshot = Bookings::BuildFinancialSnapshot.new(
        hotel: @booking.hotel,
        booking: @booking,
        check_in: @booking.check_in,
        check_out: @booking.check_out,
        guest_country: @booking.guest_country,
        room_items: room_items
      ).call
      @booking.update!(tax_lines: snapshot.tax_lines, tax_posting_snapshot: snapshot.tax_posting_snapshot)
      primary = @booking.booking_folio || @booking.booking_folios.first
      Folios::SyncForecastedCharges.call(booking_folio: primary) if primary
    end

    private

    def room_items
      @booking.booking_rooms.map do |room|
        { quantity: room.quantity.to_i.positive? ? room.quantity : 1, nightly_rate_snapshot: room.nightly_rate_snapshot }
      end
    end
  end
end
