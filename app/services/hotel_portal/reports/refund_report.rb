# frozen_string_literal: true

module HotelPortal
  module Reports
    class RefundReport
      Result = Struct.new(:start_date, :end_date, :totals, :rows, keyword_init: true)

      def initialize(hotel:, start_date:, end_date:, date_preset: nil)
        @hotel = hotel
        @start_date = start_date.to_date
        @end_date = end_date.to_date
      end

      def call
        transactions = FolioTransaction
          .joins(booking_folio: :booking)
          .includes(:user, booking_folio: [ booking: [ :refund_request, { booking_rooms: :room_type } ] ])
          .where(bookings: { hotel_id: @hotel.id })
          .where(posting_date: @start_date..@end_date)
          .where(transaction_type: :payment, category: "refund", voided_by_transaction_id: nil)
          .order(posting_date: :desc, created_at: :desc)

        rows = transactions.map { |transaction| transaction_row(transaction) }

        Result.new(
          start_date: @start_date,
          end_date: @end_date,
          totals: {
            refund_count: transactions.size,
            total_amount: transactions.sum { |transaction| transaction.amount.to_d.abs }.round(2)
          },
          rows: rows
        )
      end

      private

      def transaction_row(transaction)
        booking = transaction.booking_folio.booking
        refund_request = booking.refund_request
        metadata = transaction.metadata.to_h

        {
          date: transaction.posting_date.to_date,
          booking_reference: booking.confirmation_token,
          guest_name: booking.guest_name,
          room: room_label(booking),
          refund_method: refund_method_label(transaction, refund_request),
          reference: refund_reference(metadata, refund_request),
          status: refund_request&.status&.humanize || "Recorded",
          reason: refund_request&.reason.presence || transaction.description,
          refund_amount: transaction.amount.to_d.abs.round(2)
        }
      end

      def room_label(booking)
        names = booking.booking_rooms.filter_map { |booking_room| booking_room.room_type&.name }.uniq
        names.presence&.join(", ") || "—"
      end

      def refund_method_label(transaction, refund_request)
        metadata = transaction.metadata.to_h
        source = ::Folios::RefundSource.fetch(metadata["refund_source"] || metadata["posting_source"])
        return source.display_label if source.present?
        return "Refund request" if refund_request.present?

        "Refund"
      end

      def refund_reference(metadata, refund_request)
        metadata["reference"].presence ||
          metadata["payment_reference"].presence ||
          (refund_request.present? ? "Request ##{refund_request.id}" : "—")
      end
    end
  end
end
