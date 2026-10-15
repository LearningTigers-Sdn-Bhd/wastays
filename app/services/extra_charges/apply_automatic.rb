# frozen_string_literal: true

module ExtraCharges
  # Schedules every active auto-apply extra charge on a new booking. Charges
  # that are not per night go on the first night, once for the whole stay.
  class ApplyAutomatic
    Result = ApplicationResult.define(:forecasts)

    def self.call(booking:, user: nil)
      new(booking:, user:).call
    end

    def initialize(booking:, user:)
      @booking = booking
      @user = user
    end

    def call
      folio = @booking.booking_folio
      return Result.success(forecasts: []) if folio.blank?

      forecasts = []
      extra_charges.each do |extra_charge|
        result = CreateForecasts.call(
          extra_charge:, folio:, booking: @booking, user: @user,
          starts_on: nil, ends_on: nil, unit_rate: nil, expected_fingerprint: nil
        )
        return Result.failure("#{extra_charge.name}: #{result.error}") unless result.success?

        forecasts.concat(result.forecasts)
      end
      Result.success(forecasts:)
    end

    private

    def extra_charges
      @booking.hotel.hotel_extra_charges.auto_applied.active.ordered
        .includes(transaction_code: :transaction_code_taxes)
    end
  end
end
