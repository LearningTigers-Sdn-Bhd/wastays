# frozen_string_literal: true

module Folios
  class SyncForecastedCharges
    def self.call(booking_folio:)
      new(booking_folio:).call
    end

    def initialize(booking_folio:)
      @booking_folio = booking_folio
      @booking = booking_folio.booking
    end

    def call
      @booking_folio.with_lock do
        @booking.reload
        @booking_folio.reload

        return supersede_active_forecasts if forecasts_not_applicable?

        sync_expected_forecasts
      end
    end

    private

    def forecasts_not_applicable?
      @booking_folio.status == "closed" || @booking.status.in?(%w[cancelled completed no_show])
    end

    def sync_expected_forecasts
      lines = expected_lines
      expected_keys = lines.to_h { |line| [ forecast_key(line), line ] }

      @booking_folio.folio_forecasted_charges.forecast.find_each do |forecast|
        expected_line = expected_keys[forecast_key(forecast)]

        if expected_line.blank? || posted?(expected_line) || forecast_changed?(forecast, expected_line)
          forecast.supersede!
        end
      end

      lines.each do |line|
        next if posted?(line)
        next if actualized_forecast_exists?(line)
        next if active_forecast_exists?(line)

        @booking_folio.folio_forecasted_charges.create!(line.slice(:stay_date, :charge_kind, :identity, :amount, :description))
      end
    end

    def supersede_active_forecasts
      @booking_folio.folio_forecasted_charges.supersede_all!
    end

    def expected_lines
      ForecastedChargeLines.call(booking: @booking)
    end

    def active_forecast_exists?(line)
      @booking_folio.folio_forecasted_charges.forecast.exists?(
        stay_date: line[:stay_date],
        charge_kind: line[:charge_kind],
        identity: line[:identity]
      )
    end

    def actualized_forecast_exists?(line)
      @booking_folio.folio_forecasted_charges.actualized.exists?(
        stay_date: line[:stay_date],
        charge_kind: line[:charge_kind],
        identity: line[:identity]
      )
    end

    def forecast_changed?(forecast, line)
      forecast.amount != line[:amount].to_d || forecast.description != line[:description]
    end

    def posted?(line)
      posted_charge_scope(line).exists?
    end

    def posted_charge_scope(line)
      nightly_key = ChargePostingKeys.nightly_charge_key(
        booking: @booking,
        date: line[:stay_date],
        charge_kind: line[:charge_kind],
        identity: line[:identity]
      )
      catch_up_key = ChargePostingKeys.catch_up_charge_key(
        booking: @booking,
        date: line[:stay_date],
        charge_kind: line[:charge_kind],
        identity: line[:identity]
      )

      @booking_folio.folio_transactions.charge.where(
        "metadata->>'nightly_charge_key' = :nightly_key OR metadata->>'catch_up_key' = :catch_up_key",
        nightly_key: nightly_key,
        catch_up_key: catch_up_key
      ).where(voided_by_transaction_id: nil)
    end

    def forecast_key(record)
      [ record[:stay_date].to_date, record[:charge_kind], record[:identity] ]
    end
  end
end
