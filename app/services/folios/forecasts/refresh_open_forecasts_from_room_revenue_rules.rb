# frozen_string_literal: true

module Folios
  module Forecasts
    class RefreshOpenForecastsFromRoomRevenueRules
      include Charges::NightlyChargeCalculation

      Result = Struct.new(:folios_scanned, :bookings_updated, :forecasts_superseded, :forecasts_created, keyword_init: true) do
        def forecasts_changed
          forecasts_superseded + forecasts_created
        end
      end

      EXCLUDED_BOOKING_STATUSES = %w[cancelled completed no_show voided].freeze

      def self.call(hotel:, actor: nil)
        new(hotel: hotel, actor: actor).call
      end

      def initialize(hotel:, actor: nil)
        @hotel = hotel
        @actor = actor
        @folios_scanned = 0
        @bookings_updated = 0
        @forecasts_superseded = 0
        @forecasts_created = 0
      end

      def call
        eligible_folios.find_each do |folio|
          refresh_folio!(folio)
        end

        result = Result.new(
          folios_scanned: @folios_scanned,
          bookings_updated: @bookings_updated,
          forecasts_superseded: @forecasts_superseded,
          forecasts_created: @forecasts_created
        )
        record_audit_event!(result)
        result
      end

      private

      def eligible_folios
        @hotel.booking_folios
          .open
          .joins(:booking)
          .where.not(bookings: { status: EXCLUDED_BOOKING_STATUSES })
          .includes(booking: :booking_rooms)
      end

      def refresh_folio!(folio)
        @folios_scanned += 1

        folio.with_lock do
          folio.reload
          booking = folio.booking
          next if booking.blank? || EXCLUDED_BOOKING_STATUSES.include?(booking.status)

          before_ids = folio.folio_forecasted_charges.forecast.pluck(:id)
          update_booking_snapshot!(booking)
          Folios::Forecasts::SyncForecastedCharges.call(booking_folio: folio)
          count_forecast_changes!(folio, before_ids)
        end
      end

      def update_booking_snapshot!(booking)
        snapshot = Bookings::BuildFinancialSnapshot.new(
          hotel: @hotel,
          check_in: booking.check_in,
          check_out: booking.check_out,
          guest_country: booking.guest_country,
          room_items: room_items_for(booking)
        ).call

        attributes = {
          tax_lines: snapshot.tax_lines,
          tax_posting_snapshot: snapshot.tax_posting_snapshot
        }
        return unless booking.tax_lines != attributes[:tax_lines] || booking.tax_posting_snapshot != attributes[:tax_posting_snapshot]

        booking.update!(attributes)
        @bookings_updated += 1
      end

      def room_items_for(booking)
        booking.booking_rooms.map do |room|
          quantity = room.quantity.to_i.positive? ? room.quantity.to_i : 1

          {
            quantity: quantity,
            nightly_rate_snapshot: snapshot_for_room(room, quantity)
          }
        end
      end

      def snapshot_for_room(room, quantity)
        Bookings::ScheduledStay.stay_dates(
          hotel: room.booking.hotel,
          check_in: room.booking.check_in,
          check_out: room.booking.check_out
        ).index_with do |date|
          amount = nightly_room_amount(room, date)
          price = quantity.positive? ? amount.to_d / quantity : amount.to_d

          {
            "date" => date.iso8601,
            "price" => price.round(2).to_s("F"),
            "currency" => room.booking.currency.presence || @hotel.default_currency.presence || "MYR",
            "source" => "forecast_refresh"
          }
        end.transform_keys(&:iso8601)
      end

      def count_forecast_changes!(folio, before_ids)
        @forecasts_superseded += folio.folio_forecasted_charges.superseded.where(id: before_ids).count
        @forecasts_created += folio.folio_forecasted_charges.forecast.where.not(id: before_ids).count
      end

      def record_audit_event!(result)
        FinancialControls::AuditEventRecorder.call!(
          hotel: @hotel,
          business_date: @hotel.current_business_date,
          event_type: "folio_forecasts_refreshed",
          source: "transaction_codes",
          actor: @actor,
          reason: "ROOM transaction code tax rules applied to open folio forecasts",
          metadata: {
            room_revenue_tax_rule_application: @hotel.transaction_configuration.room_revenue_tax_rule_application,
            folios_scanned: result.folios_scanned,
            bookings_updated: result.bookings_updated,
            forecasts_superseded: result.forecasts_superseded,
            forecasts_created: result.forecasts_created,
            forecasts_changed: result.forecasts_changed
          }
        )
      end
    end
  end
end
