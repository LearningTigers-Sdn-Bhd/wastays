# frozen_string_literal: true

module HotelPortal
  module Reports
    class DailyRevenueTransactionRow
      attr_reader :transaction

      delegate :posting_date, :posted_at, :transaction_type, :category, :description,
        :currency, to: :transaction

      def initialize(transaction)
        @transaction = transaction
      end

      def booking
        transaction.booking_folio.booking
      end

      def folio
        transaction.booking_folio
      end

      def transaction_code
        transaction.transaction_code&.code.presence || "—"
      end

      def service_name
        transaction.transaction_code&.name.presence || description.presence || category.to_s.humanize
      end

      def booking_reference
        booking.confirmation_token
      end

      def folio_number
        folio.folio_reference_display
      end

      def guest_name
        booking.guest_name.presence || "—"
      end

      def room_number
        folio.booking_room&.room_number.presence || booking.booking_rooms.first&.room_number.presence || "—"
      end

      def payment_method
        metadata["payment_source"].presence || metadata["refund_source"].presence
      end

      def posting_source
        metadata["posting_source"].presence || "—"
      end

      def actor_name
        transaction.user&.name.presence || (posting_source == "—" ? "—" : posting_source.humanize)
      end

      def stay_date
        metadata["stay_date"].presence
      end

      def signed_amount
        transaction.amount.to_d
      end

      def relationship_status
        return "Reversal" if transaction.reversal_of_transaction_id.present?
        return "Reversed" if transaction.voided_by_transaction_id.present?

        "Original"
      end

      def related_transaction_id
        transaction.reversal_of_transaction_id || transaction.voided_by_transaction_id
      end

      private

      def metadata
        transaction.metadata.to_h.stringify_keys
      end
    end
  end
end
