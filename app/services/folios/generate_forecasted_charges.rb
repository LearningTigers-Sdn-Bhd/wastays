module Folios
  class GenerateForecastedCharges
    def self.call(booking_folio:)
      new(booking_folio:).call
    end

    def initialize(booking_folio:)
      @booking_folio = booking_folio
    end

    def call
      ForecastedChargeLines.call(booking: @booking_folio.booking).each do |line|
        next if forecast_exists?(line)
        next if posted?(line)

        create_forecast!(line)
      end
    end

    private

    def create_forecast!(line)
      @booking_folio.folio_forecasted_charges.create!(line)
    rescue ActiveRecord::RecordNotUnique
      # The partial unique index is the final guard for concurrent generation.
      nil
    end

    def forecast_exists?(line)
      @booking_folio.folio_forecasted_charges.where(
        stay_date: line[:stay_date],
        charge_kind: line[:charge_kind],
        identity: line[:identity]
      ).where(status: %w[forecast actualized]).exists?
    end

    def posted?(line)
      booking = @booking_folio.booking
      nightly_key = ChargePostingKeys.nightly_charge_key(
        booking: booking,
        date: line[:stay_date],
        charge_kind: line[:charge_kind],
        identity: line[:identity]
      )
      catch_up_key = ChargePostingKeys.catch_up_charge_key(
        booking: booking,
        date: line[:stay_date],
        charge_kind: line[:charge_kind],
        identity: line[:identity]
      )

      @booking_folio.folio_transactions.charge.where(
        "metadata->>'nightly_charge_key' = :nightly_key OR metadata->>'catch_up_key' = :catch_up_key",
        nightly_key: nightly_key,
        catch_up_key: catch_up_key
      ).where(voided_by_transaction_id: nil).exists?
    end
  end
end
