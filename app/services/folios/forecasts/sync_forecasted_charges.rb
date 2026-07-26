# frozen_string_literal: true

module Folios
  module Forecasts
    class SyncForecastedCharges
      def self.call(booking_folio:)
        new(booking_folio:).call
      end

      def initialize(booking_folio:)
        @booking_folio = booking_folio
        @booking = booking_folio.booking
      end

      def call
        @booking.with_lock do
          @booking.reload
          booking_folios.each(&:reload)

          return supersede_active_forecasts if forecasts_not_applicable?

          sync_expected_forecasts
        end
      end

      private

      def forecasts_not_applicable?
        @booking.status.in?(%w[cancelled completed no_show voided])
      end

      def sync_expected_forecasts
        lines = expected_lines
        expected_keys = lines.to_h { |line| [ forecast_key(line), line ] }

        active_forecasts.find_each do |forecast|
          expected_line = expected_keys[forecast_key(forecast)]
          posted_transaction = expected_line.present? ? posted_transaction_for(expected_line) : nil

          if expected_line.blank?
            forecast.supersede!
          elsif posted_transaction.present?
            if posted_transaction.booking_folio_id == forecast.booking_folio_id
              forecast.actualize!(transaction: posted_transaction)
            else
              forecast.supersede!
            end
          elsif routed_target_folio(expected_line)&.id != forecast.booking_folio_id || forecast_changed?(forecast, expected_line)
            forecast.supersede!
          end
        end

        lines.each do |line|
          target_folio = routed_target_folio(line)
          next if target_folio.blank?
          next if posted_transaction_for(line).present?
          next if actualized_forecast_exists?(line)
          next if active_forecast_exists?(line, target_folio)

          target_folio.folio_forecasted_charges.create!(line.slice(:stay_date, :charge_kind, :identity, :amount, :description))
        end
      end

      def supersede_active_forecasts
        active_forecasts.update_all(status: "superseded", updated_at: Time.current)
      end

      def expected_lines
        Reads::ForecastedChargeLines.call(booking: @booking)
      end

      def active_forecast_exists?(line, folio)
        folio.folio_forecasted_charges.forecast.exists?(
          stay_date: line[:stay_date],
          charge_kind: line[:charge_kind],
          identity: line[:identity]
        )
      end

      def actualized_forecast_exists?(line)
        booking_forecasts.actualized.exists?(
          stay_date: line[:stay_date],
          charge_kind: line[:charge_kind],
          identity: line[:identity]
        )
      end

      def forecast_changed?(forecast, line)
        forecast.amount != line[:amount].to_d || forecast.description != line[:description]
      end

      def posted_transaction_for(line)
        @posted_transactions_by_key ||= {}
        @posted_transactions_by_key[forecast_key(line)] ||= posted_charge_scope(line).first
      end

      def posted_charge_scope(line)
        nightly_key = Charges::ChargePostingKeys.nightly_charge_key(
          booking: @booking,
          date: line[:stay_date],
          charge_kind: line[:charge_kind],
          identity: line[:identity]
        )
        catch_up_key = Charges::ChargePostingKeys.catch_up_charge_key(
          booking: @booking,
          date: line[:stay_date],
          charge_kind: line[:charge_kind],
          identity: line[:identity]
        )

        FolioTransaction.joins(:booking_folio)
          .where(booking_folios: { booking_id: @booking.id })
          .charge
          .where(
            "metadata->>'nightly_charge_key' = :nightly_key OR metadata->>'reconciles_nightly_charge_key' = :nightly_key OR catch_up_key = :catch_up_key OR metadata->>'catch_up_key' = :catch_up_key",
            nightly_key: nightly_key,
            catch_up_key: catch_up_key
          )
          .where(voided_by_transaction_id: nil)
          .order(:posting_date, :created_at, :id)
      end

      def forecast_key(record)
        [ record[:stay_date].to_date, record[:charge_kind], record[:identity] ]
      end

      def routed_target_folio(line)
        @routed_target_folios ||= {}
        @routed_target_folios[forecast_key(line)] ||= begin
          route = Folios::Routing::ResolveTargetFolio.call(
            booking: @booking,
            transaction_code: line[:transaction_code],
            fallback_transaction_code: line[:fallback_transaction_code]
          )
          route.success? ? route.folio : nil
        end
      end

      def active_forecasts
        booking_forecasts.forecast
      end

      def booking_forecasts
        FolioForecastedCharge.where(booking_folio_id: booking_folios.map(&:id))
      end

      def booking_folios
        @booking_folios ||= @booking.booking_folios.includes(:folio_forecasted_charges).to_a
      end
    end
  end
end
