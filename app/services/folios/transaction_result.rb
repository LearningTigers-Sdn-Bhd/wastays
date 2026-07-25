# frozen_string_literal: true

module Folios
  # What posting to a folio answers. Most postings produce one transaction;
  # reversals produce the parent and its tax lines together, and a taxable staff
  # charge attaches the tax lines it posted alongside the parent.
  TransactionResult = ApplicationResult.define(:transaction, :transactions, :tax_transactions)
end
