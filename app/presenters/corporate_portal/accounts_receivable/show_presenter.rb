# frozen_string_literal: true

module CorporatePortal
  module AccountsReceivable
    class ShowPresenter
      AllocationRow = Struct.new(:received_on, :reference, :payment_method, :allocated_amount, keyword_init: true)

      attr_reader :invoice

      def initialize(invoice:)
        @invoice = invoice
      end

      def invoice_label
        invoice.formatted_invoice_number
      end

      def hotel_name
        invoice.hotel.name
      end

      def booking_reference
        invoice.booking.confirmation_token.presence || "—"
      end

      def folio_reference
        invoice.booking_folio.folio_reference_display.presence || "—"
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

      def has_outstanding_balance?
        invoice.outstanding_amount.to_d.positive?
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
              allocated_amount: "#{payment.currency} #{format("%.2f", allocation.amount.to_d)}"
            )
          end
      end

      private

      def metadata
        @metadata ||= invoice.metadata.to_h.stringify_keys
      end

      def money_label(amount)
        "#{invoice.currency} #{format("%.2f", amount.to_d)}"
      end

      def format_date(value)
        value&.strftime("%d %b %Y") || "—"
      end

      def format_datetime(value)
        value&.in_time_zone(invoice.hotel.hotel_time_zone)&.strftime("%d %b %Y, %I:%M %p") || "—"
      end
    end
  end
end
