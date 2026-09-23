# frozen_string_literal: true

module Bookings
  # What a guest owes on one booking, and what they have paid.
  #
  # The total is every charge on the booking's folios, posted or still
  # forecast for a night not yet run. A booking with no folio charges yet
  # falls back to its booked total, so a prepaid stay does not read as free.
  #
  # A booking paid online (payment captured) counts as paid for its booked
  # total even before the payment reaches a folio. The larger of the two is
  # taken, so a payment that is in both places is not counted twice.
  #
  # The registration card and the guest portal both read this, so the front
  # desk and the guest see the same numbers.
  class GuestBalance
    Result = Data.define(:total, :paid, :due)

    def initialize(booking:)
      @booking = booking
    end

    def call
      folios = @booking.booking_folios.to_a
      charges = folios.sum(0.to_d) { |folio| folio.total_charges.to_d + folio.projected_forecasts.sum(&:amount).to_d }
      total = charges.positive? ? charges : @booking.total_amount.to_d
      folio_paid = folios.sum(0.to_d) { |folio| folio.total_payments.to_d }
      paid = [ folio_paid, (@booking.payment_concluded? ? @booking.total_amount.to_d : 0.to_d) ].max

      Result.new(total:, paid:, due: total - paid)
    end
  end
end
