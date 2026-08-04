# frozen_string_literal: true

module Discounts
  class Post
    Result = ApplicationResult.define(:transaction, :transactions, :tax_transactions, :quote)

    def self.call(discount:, folio:, user:, posting_date:, requested_amount:, expected_fingerprint:, description: nil, reference: nil, note: nil)
      quote = Quote.call(discount:, folio:, posting_date:, requested_amount:, expected_fingerprint:)
      return Result.failure(quote.error, quote:) unless quote.success?

      metadata = quote.metadata.merge(reference: reference.to_s.strip.presence, note: note.to_s.strip.presence).compact
      result = Folios::Transactions::PostStaffTransaction.call(
        folio:, user:, transaction_type: "adjustment", category: "discount", amount: -quote.amount.abs,
        description: Description.call(discount:, currency: folio.currency, quote:, submitted_description: description),
        posting_date:, transaction_code_id: discount.transaction_code_id, options: { metadata: }
      )
      if result.success?
        Result.success(transaction: result.transaction, transactions: result.transactions, tax_transactions: result.tax_transactions, quote:)
      else
        Result.failure(result.error, quote:)
      end
    end
  end
end
