# frozen_string_literal: true

module Reports
  module AccountsReceivable
    class GenerateInvoiceRecords
      Line = Data.define(:date, :code, :description, :amount)

      attr_reader :invoice, :printed_by

      def initialize(invoice:, printed_by: nil)
        @invoice = invoice
        @printed_by = printed_by.presence || "-"
        @snapshot = if invoice.invoice&.current_revision
          invoice.invoice.current_revision.snapshot.to_h.deep_stringify_keys
        else
          invoice.metadata.to_h["document_snapshot"].to_h.deep_stringify_keys
        end
      end

      def invoice_reference
        invoice.formatted_invoice_number
      end

      def legacy_generated?
        invoice.invoice&.legacy? || @snapshot.empty? || @snapshot["legacy_generated"] == true
      end

      def company_name
        snapshot_or_live("payer", "name") { invoice.corporate_account.name }.presence || "-"
      end

      def account_type
        value = snapshot_or_live("payer", "account_type") { invoice.hotel_corporate_account.account_type }
        value.to_s.humanize.presence || "-"
      end

      def booking_reference
        snapshot_or_live("booking", "confirmation_token") { invoice.booking.confirmation_token }.presence || "-"
      end

      def folio_reference
        snapshot_or_live("folio", "folio_reference") { invoice.booking_folio.folio_reference_display }.presence || "-"
      end

      def room_reference
        rooms = @snapshot["rooms"]
        return live_room_reference unless @snapshot.key?("rooms")

        Array(rooms).map do |room|
          room = room.to_h.stringify_keys
          [ room["room_number"], room["room_type"] ].compact_blank.join(" / ")
        end.compact_blank.join(", ").presence || "-"
      end

      def purchase_order_reference
        snapshot_or_live("payer", "purchase_order_reference") { live_terms&.purchase_order_reference }.presence || "-"
      end

      def authorization_reference
        snapshot_or_live("payer", "authorization_reference") { live_terms&.authorization_reference }.presence || "-"
      end

      def payment_terms
        days = snapshot_value("payer", "payment_terms_days")
        days = invoice.metadata.to_h["payment_terms_days"] if days.nil?
        days = invoice.hotel_corporate_account.payment_terms_days if days.nil?
        return "-" if days.nil?
        return "Due on receipt" if days.to_i.zero?

        "Net #{days.to_i} days"
      end

      def status
        invoice.status.humanize
      end

      def currency
        invoice.currency
      end

      def issued_on
        format_date(invoice.issued_on)
      end

      def due_on
        format_date(invoice.due_on)
      end

      def original_amount
        invoice.amount.to_d
      end

      def paid_amount
        invoice.paid_amount.to_d
      end

      def outstanding_amount
        invoice.outstanding_amount.to_d
      end

      def lines
        @lines ||= source_transactions.filter_map do |transaction|
          transaction = transaction.to_h.stringify_keys
          next if transaction["reversal_of_transaction_id"].present? || transaction["voided_by_transaction_id"].present?

          amount = transaction["amount"].to_d
          amount = -amount if transaction["transaction_type"] == "payment"

          Line.new(
            transaction["posting_date"].present? ? format_date(Date.iso8601(transaction["posting_date"].to_s)) : "-",
            transaction["code"].presence || transaction["category"].to_s.upcase,
            line_description(transaction),
            amount
          )
        end
      end

      def line_total
        lines.sum { |line| line.amount.to_d }
      end

      private

      def snapshot_value(*keys)
        @snapshot.dig(*keys)
      end

      def snapshot_or_live(section, key)
        values = @snapshot[section]
        return values[key] if values.is_a?(Hash) && values.key?(key)

        yield
      end

      def line_description(transaction)
        description = transaction["description"].presence || transaction["category"].to_s.humanize
        return "Payment - #{description}" if transaction["transaction_type"] == "payment" && transaction["amount"].to_d.positive?
        return "Refund - #{description}" if transaction["transaction_type"] == "payment"

        description
      end

      def source_transactions
        transactions = @snapshot["transactions"]
        return transactions if transactions.is_a?(Array)

        invoice.booking_folio.folio_transactions.includes(:transaction_code).order(:posting_date, :created_at, :id).map do |transaction|
          {
            transaction_type: transaction.transaction_type,
            category: transaction.category,
            code: transaction.transaction_code&.code,
            description: transaction.description,
            amount: transaction.amount.to_d.to_s("F"),
            posting_date: transaction.posting_date&.iso8601,
            reversal_of_transaction_id: transaction.reversal_of_transaction_id,
            voided_by_transaction_id: transaction.voided_by_transaction_id
          }
        end
      end

      def live_terms
        invoice.booking_folio.booking_billing_party&.billing_terms
      end

      def live_room_reference
        folio = invoice.booking_folio
        rooms = folio.booking_room.present? ? [ folio.booking_room ] : invoice.booking.booking_rooms.includes(:room_type)
        rooms.map do |room|
          type = room.room_type_snapshot.to_h["name"].presence || room.room_type&.name
          [ room.room_number.presence, type ].compact.join(" / ").presence
        end.compact.join(", ").presence || "-"
      end

      def format_date(value)
        value&.strftime("%d %b %Y") || "-"
      end
    end
  end
end
