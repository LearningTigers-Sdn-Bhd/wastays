# frozen_string_literal: true

module Notifications
  module PayloadBuilders
    class CheckOutReceiptMessage
      def initialize(booking:)
        @booking = booking
      end

      def call
        line_items = build_line_items
        line_items_total = line_items.sum { |item| item[:amount].to_f }.round(2)
        tax_total = tourism_tax_total
        derived_grand_total = (line_items_total + tax_total).round(2)
        booking_total = @booking.total_amount.to_f.round(2)
        mismatch_amount = (booking_total - derived_grand_total).round(2)

        {
          notification_type: "check_out_receipt_message",
          trigger_event: "booking_completed",
          booking_id: @booking.id,
          confirmation_token: @booking.confirmation_token,
          guest_name: @booking.guest_name,
          guest_phone: @booking.guest_phone,
          guest_email: @booking.guest_email,
          hotel_name: @booking.hotel.name,
          check_in: @booking.check_in&.iso8601,
          check_out: @booking.check_out&.iso8601,
          checked_out_at: @booking.checked_out_at&.iso8601,
          currency: @booking.currency,
          line_items: line_items,
          tax_line: build_tax_line,
          line_items_total: line_items_total,
          tax_total: tax_total,
          derived_grand_total: derived_grand_total,
          booking_total: booking_total,
          totals_mismatch: !mismatch_amount.zero?,
          totals_mismatch_amount: mismatch_amount,
          invoice_url: invoice_url_for(@booking)
        }
      end

      private

      def build_line_items
        @booking.booking_rooms.map do |booking_room|
          {
            description: room_description(booking_room),
            quantity: booking_room.quantity.to_i,
            amount: booking_room.subtotal.to_f.round(2),
            room_number: booking_room.room_number.presence
          }
        end
      end

      def room_description(booking_room)
        snapshot_name = booking_room.room_type_snapshot.to_h["name"].presence
        snapshot_name || booking_room.room_type&.name || "Room charge"
      end

      def tourism_tax_total
        return 0.0 unless @booking.tourism_tax?

        @booking.tourism_tax_amount.to_f.round(2)
      end

      def build_tax_line
        return nil unless @booking.tourism_tax?

        {
          description: "Tourism tax",
          quantity: 1,
          amount: tourism_tax_total
        }
      end

      def invoice_url_for(booking)
        host_options = Rails.application.config.action_mailer.default_url_options || {}

        Rails.application.routes.url_helpers.invoice_booking_url(
          booking.confirmation_token,
          host: host_options[:host],
          protocol: host_options[:protocol] || "https"
        )
      end
    end
  end
end
