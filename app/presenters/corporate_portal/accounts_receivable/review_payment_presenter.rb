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
      def selected_total = snapshots.sum { |snapshot| value(snapshot, "outstanding_amount").to_d }
      def selected_total_label = money(selected_total)
      def excess_label = money([ intent.amount.to_d - selected_total, 0.to_d ].max)
      def shortfall_label = money([ selected_total - intent.amount.to_d, 0.to_d ].max)

      private

      def money(amount)
        "#{intent.currency} #{format('%.2f', amount.to_d)}"
      end

      def value(hash, key)
        hash[key] || hash[key.to_sym]
      end
    end
  end
end
