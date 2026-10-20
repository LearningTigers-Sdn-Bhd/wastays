# frozen_string_literal: true

module Folios
  module Routing
    # Moves a booking's upcoming scheduled extra charges onto the folio their
    # routing rule now names. A scheduled extra posts to the folio it is
    # scheduled on, so a route added after the booking was made only reaches it
    # once it has been moved. A tax line follows the charge it belongs to.
    class RerouteScheduledExtras
      def self.call(booking:)
        new(booking:).call
      end

      def initialize(booking:)
        @booking = booking
      end

      def call
        replacements = {}
        forecasts = FolioForecastedCharge.forecast.scheduled_extra_charges.where(source_booking_id: @booking.id)
          .includes(:booking_folio).order(Arel.sql("CASE charge_kind WHEN 'extra_charge' THEN 0 ELSE 1 END"), :id)
        forecasts.each do |forecast|
          metadata = forecast.metadata.deep_dup
          parent = replacements[metadata["parent_forecast_id"]]
          code = @booking.hotel.transaction_codes.find_by(id: metadata["transaction_code_id"])
          next if code.blank?

          rule = @booking.folio_routing_rules.active.find_by(transaction_code: code)
          target = if rule
            route = Folios::Routing::ResolveTargetFolio.call(booking: @booking, transaction_code: code, posting_date: forecast.stay_date)
            raise route.error unless route.success?
            route.folio
          elsif parent
            parent.booking_folio
          else
            forecast.booking_folio
          end
          next if target.id == forecast.booking_folio_id && parent.nil?

          metadata["parent_forecast_id"] = parent.id if parent
          forecast.supersede!
          replacement = target.folio_forecasted_charges.create!(source_booking: @booking, stay_date: forecast.stay_date,
            charge_kind: forecast.charge_kind, identity: forecast.identity, amount: forecast.amount,
            description: forecast.description, metadata:)
          replacements[forecast.id] = replacement
        end
      end
    end
  end
end
