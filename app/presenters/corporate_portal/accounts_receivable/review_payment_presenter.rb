# frozen_string_literal: true

module CorporatePortal
  module AccountsReceivable
    class ReviewPaymentPresenter
      attr_reader :intent

      def initialize(intent:)
        @intent = intent
      end

      def hotel_name = intent.hotel.name
      def amount_label = money(intent.amount)
      def currency = intent.currency
      def ready? = intent.hotel.effective_payment_setting(intent.gateway).present?
      def suggestions = intent.remittance_suggestions
      def snapshots = intent.invoice_snapshots

      # The snapshot holds invoice ids only, so guest names come from the live invoices.
      def guest_name(suggestion)
        guest_names[value(suggestion, "ar_invoice_id").to_s]
      end
      def selected_total = snapshots.sum { |snapshot| value(snapshot, "outstanding_amount").to_d }
      def selected_total_label = money(selected_total)
      def excess_label = money([ intent.amount.to_d - selected_total, 0.to_d ].max)
      def shortfall_label = money([ selected_total - intent.amount.to_d, 0.to_d ].max)

      private

      def guest_names
        @guest_names ||= begin
          ids = suggestions.filter_map { |suggestion| value(suggestion, "ar_invoice_id") }
          intent.hotel.ar_invoices.where(id: ids, hotel_corporate_account_id: intent.hotel_corporate_account_id)
            .includes(booking_folio: :booking)
            .to_h { |invoice| [ invoice.id.to_s, invoice.booking.guest_name ] }
        end
      end

      def money(amount)
        "#{intent.currency} #{format('%.2f', amount.to_d)}"
      end

      def value(hash, key)
        hash[key] || hash[key.to_sym]
      end
    end
  end
end
