# frozen_string_literal: true

module Folios
  module Routing
    class PreviewExistingCharges
      Result = Data.define(:transactions, :count, :amount)

      def self.call(rule:, through: nil)
        new(rule: rule, through: through).call
      end

      def initialize(rule:, through: nil)
        @rule = rule
        @through = through&.to_date
      end

      def call
        transactions = eligible_transactions.to_a
        Result.new(transactions: transactions, count: transactions.size, amount: transactions.sum(&:amount))
      end

      private

      def eligible_transactions
        scope = FolioTransaction
          .joins(:booking_folio)
          .where(booking_folios: { booking_id: @rule.booking_id })
          .where(transaction_type: "charge", transaction_code_id: @rule.transaction_code_id)
          .where(voided_by_transaction_id: nil, reversal_of_transaction_id: nil)
          .where.not(booking_folio_id: @rule.target_folio_id)
        scope = scope.where("posting_date >= ?", @rule.effective_from) if @rule.effective_from.present?
        scope = scope.where("posting_date <= ?", @rule.effective_until) if @rule.effective_until.present?
        scope = scope.where("posting_date <= ?", @through) if @through.present?
        scope.order(:posting_date, :id)
      end
    end
  end
end
