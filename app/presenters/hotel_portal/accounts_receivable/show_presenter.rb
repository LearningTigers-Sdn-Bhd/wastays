# frozen_string_literal: true

module HotelPortal
  module AccountsReceivable
    class ShowPresenter
      AllocationRow = Struct.new(:received_on, :reference, :payment_method, :allocated_amount, keyword_init: true)
      SnapshotRow = Struct.new(:label, :value, keyword_init: true)

      attr_reader :invoice, :hotel

      def initialize(invoice:, hotel:)
        @invoice = invoice
        @hotel = hotel
      end

      def invoice_label
        "AR-#{invoice.invoice_number}"
      end

      def company_name
        invoice.corporate_account.name
      end

      def status_label
        invoice.status.humanize
      end

      def status_class
        case invoice.status
        when "open" then "border-blue-200 bg-blue-50 text-blue-700"
        when "partially_paid" then "border-amber-200 bg-amber-50 text-amber-700"
        when "paid" then "border-emerald-200 bg-emerald-50 text-emerald-700"
        when "overdue" then "border-red-200 bg-red-50 text-red-700"
        else "border-slate-200 bg-slate-100 text-slate-600"
        end
      end

      def original_amount_label
        money_label(invoice.amount)
      end

      def paid_amount_label
        money_label(invoice.paid_amount)
      end

      def outstanding_amount_label
        money_label(invoice.outstanding_amount)
      end

      def booking_reference
        invoice.booking.confirmation_token.presence || "—"
      end

      def folio_reference
        invoice.booking_folio.folio_reference_display.presence || "—"
      end

      def payment_terms_label
        days = metadata["payment_terms_days"]
        days = invoice.hotel_corporate_account.payment_terms_days if days.nil?
        return "—" if days.nil?
        return "Due on receipt" if days.to_i.zero?

        "Net #{days.to_i} days"
      end

      def issued_on_label
        format_date(invoice.issued_on)
      end

      def due_on_label
        format_date(invoice.due_on)
      end

      def direct_bill_source_label
        metadata["direct_bill_closed_at"].present? ? "Folio close" : "—"
      end

      def created_at_label
        format_datetime(invoice.created_at)
      end

      def allocation_rows
        @allocation_rows ||= invoice.ar_payment_allocations
          .reject(&:reversed?)
          .sort_by { |allocation| [ allocation.ar_payment.received_at, allocation.id ] }
          .reverse
          .map do |allocation|
            payment = allocation.ar_payment
            AllocationRow.new(
              received_on: format_date(payment.received_at),
              reference: payment.reference_number.presence || "—",
              payment_method: payment.payment_method.to_s.humanize.presence || "—",
              allocated_amount: "#{payment.currency} #{format('%.2f', allocation.amount.to_d)}"
            )
          end
      end

      def technical_snapshot_rows
        @technical_snapshot_rows ||= metadata.sort.map do |key, value|
          SnapshotRow.new(label: key.to_s.humanize.titleize, value: snapshot_value(key.to_s, value))
        end
      end

      private

      def metadata
        @metadata ||= invoice.metadata.to_h.stringify_keys
      end

      def money_label(amount)
        "#{invoice.currency} #{format('%.2f', amount.to_d)}"
      end

      def format_date(value)
        value&.strftime("%d %b %Y") || "—"
      end

      def format_datetime(value)
        value&.in_time_zone(hotel.hotel_time_zone)&.strftime("%d %b %Y, %I:%M %p") || "—"
      end

      def snapshot_value(key, value)
        return "—" if value.blank? && value != false
        return format_snapshot_datetime(value) if key.end_with?("_at")
        return "#{value.to_i} days" if key == "payment_terms_days"
        return money_label(value) if key == "folio_balance"

        case value
        when Hash
          value.map { |nested_key, nested_value| "#{nested_key.to_s.humanize}: #{snapshot_scalar(nested_value)}" }.join(" · ")
        when Array
          value.map { |item| snapshot_scalar(item) }.join(", ")
        when TrueClass then "Yes"
        when FalseClass then "No"
        else value.to_s
        end
      end

      def format_snapshot_datetime(value)
        parsed = Time.zone.parse(value.to_s)
        parsed ? format_datetime(parsed) : value.to_s
      rescue ArgumentError, TypeError
        value.to_s
      end

      def snapshot_scalar(value)
        value.is_a?(Hash) ? value.map { |key, item| "#{key.to_s.humanize}: #{snapshot_scalar(item)}" }.join(", ") : value.to_s
      end
    end
  end
end
