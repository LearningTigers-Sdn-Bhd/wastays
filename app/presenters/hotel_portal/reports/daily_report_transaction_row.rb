# frozen_string_literal: true

module HotelPortal
  module Reports
    class DailyReportTransactionRow
      CASHIER_LIST_HEADERS = [
        "Date & Time", "Reservation", "Guest", "Room", "Folio", "Invoice",
        "Payment Mode", "Type", "Received By", "Remarks", "Amount"
      ].freeze
      CASHIER_VISUAL_HEADERS = [
        "Date & Time", "Reservation", "Guest Details", "Folio", "Invoice",
        "Payment Mode", "Type", "Received By", "Remarks", "Amount"
      ].freeze

      attr_reader :transaction

      delegate :posting_date, :posted_at, :transaction_type, :category, :description,
        :currency, to: :transaction

      def initialize(transaction, settlement_mode: nil, section: nil, origin: nil)
        @transaction = transaction
        @settlement_mode = settlement_mode
        @section = section
        @origin = origin
      end

      # Set only on rows no cashier handled: which side the money sits on.
      attr_reader :origin

      # What the movement did to the drawer: money taken before the charge
      # exists, money taken against a charge, or money given back.
      def section
        return "Refund" if category == "refund"

        @section.presence || "Settlement"
      end

      def booking
        transaction.booking_folio.booking
      end

      def folio
        transaction.booking_folio
      end

      def transaction_code
        transaction.posted_transaction_code.presence || "—"
      end

      def service_name
        transaction.posted_transaction_code_name.presence || description.presence || category.to_s.humanize
      end

      def settlement_mode
        @settlement_mode.presence || service_name
      end

      def booking_reference
        booking.confirmation_token
      end

      def folio_number
        folio.folio_reference_display
      end

      def invoice_number
        folio.invoice_number.presence || "—"
      end

      def guest_name
        booking.guest_name.presence || "—"
      end

      def room_number
        booked_room&.room_number.presence || "—"
      end

      def room_type_name
        booked_room&.room_type_snapshot.to_h["name"].presence || booked_room&.room_type&.name.presence
      end

      def room_details
        [ (room_number unless room_number == "—"), room_type_name ].compact.join(" · ").presence
      end

      def transaction_time
        posted_at || transaction.created_at
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

      def received_by
        return "Payment Gateway" if gateway_receipt?

        transaction.user&.name.presence || "—"
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

      def booked_room
        @booked_room ||= folio.booking_room || booking.booking_rooms.first
      end

      def metadata
        transaction.metadata.to_h.stringify_keys
      end

      def gateway_receipt?
        metadata["payment_transaction_id"].present? || posting_source == "gateway_payment"
      end
    end
  end
end
