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
      end

      private

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
