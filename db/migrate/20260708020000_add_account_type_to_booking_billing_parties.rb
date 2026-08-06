# frozen_string_literal: true

class AddAccountTypeToBookingBillingParties < ActiveRecord::Migration[8.0]
  def change
    add_column :booking_billing_parties, :account_type, :string
    add_check_constraint :booking_billing_parties,
      "account_type IS NULL OR account_type IN ('company', 'government', 'travel_agent')",
      name: "booking_billing_parties_account_type_allowed"
  end
end
