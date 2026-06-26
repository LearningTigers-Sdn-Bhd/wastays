# frozen_string_literal: true

class AddCorporateArLinksToPaymentTransactions < ActiveRecord::Migration[8.0]
  def change
    add_reference :payment_transactions, :corporate_ar_payment_intent, null: true, foreign_key: true, index: { name: "idx_payment_transactions_on_corp_ar_intent_id" }
    add_reference :payment_transactions, :ar_payment, null: true, foreign_key: true
  end
end
