# frozen_string_literal: true

module Folios
  module Routing
    class RefreshBookingForecasts
      def self.call(booking:)
        new(booking:).call
      end

      def initialize(booking:)
        @booking = booking
      end

      def call
        ota_snapshot = current_ota_snapshot
        if ota_snapshot
          ChannelManagers::Financials::ProjectBookingSnapshots.call!(snapshot: ota_snapshot)
        else
          rebuild_pms_snapshot!
        end

        primary = @booking.booking_folio || @booking.booking_folios.first
        Folios::Forecasts::SyncForecastedCharges.call(booking_folio: primary) if primary
        reroute_scheduled_extras!
      end

      private

      def reroute_scheduled_extras!
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

      def current_ota_snapshot
        OtaFinancialSnapshot.current
          .where("booking_id = :booking_id OR group_booking_id = :group_booking_id",
            booking_id: @booking.id, group_booking_id: @booking.group_booking_id)
          .order(created_at: :desc, id: :desc)
          .first
      end

      def rebuild_pms_snapshot!
        snapshot = Bookings::BuildFinancialSnapshot.new(
          hotel: @booking.hotel,
          booking: @booking,
          check_in: @booking.check_in,
          check_out: @booking.check_out,
          guest_country: @booking.guest_country,
          room_items: room_items
        ).call
        @booking.update!(tax_lines: snapshot.tax_lines, tax_posting_snapshot: snapshot.tax_posting_snapshot)
      end

      def room_items
        @booking.booking_rooms.map do |room|
          { quantity: room.quantity.to_i.positive? ? room.quantity : 1, nightly_rate_snapshot: room.nightly_rate_snapshot }
        end
      end
    end
  end
end
