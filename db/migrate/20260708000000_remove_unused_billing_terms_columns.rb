# frozen_string_literal: true

class RemoveUnusedBillingTermsColumns < ActiveRecord::Migration[8.0]
  def change
    remove_column :booking_billing_terms, :preferred_payment_method, :string
    remove_column :booking_billing_terms, :billing_reference, :string
  end
end
