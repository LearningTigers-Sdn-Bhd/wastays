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
        tax_total = @booking.tax_total
        derived_grand_total = (line_items_total + tax_total).round(2)
        booking_total = @booking.total_amount.to_f.round(2)
        mismatch_amount = (booking_total - derived_grand_total).round(2)
        has_outstanding = @booking.folio_outstanding_balance > 0
        document_type = has_outstanding ? "invoice" : "receipt"

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
          document_type: document_type,
          invoice_url: document_url_for(@booking, document_type)
        }
      end

      private

      def build_line_items
        @booking.booking_rooms.map do |booking_room|
          {
            description: room_description(booking_room),
            quantity: 1,
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
        @booking.tax_lines_for("ttx").sum { |t| t["amount"].to_f }.round(2)
      end

      def build_tax_line
        lines = Array(@booking.tax_lines)
        return nil if lines.empty?

        lines.map { |t| { description: t["name"], quantity: 1, amount: t["amount"].to_f } }
      end

      def document_url_for(booking, document_type)
        host_options = Rails.application.config.action_mailer.default_url_options || {}
        route = document_type == "invoice" ? :invoice_booking_url : :receipt_booking_url

        Rails.application.routes.url_helpers.public_send(
          route,
          booking.confirmation_token,
          host: host_options[:host],
          protocol: host_options[:protocol] || "https"
        )
      end
    end
  end
end
