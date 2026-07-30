# frozen_string_literal: true

class AddSalespersonAccountType < ActiveRecord::Migration[8.0]
  def up
    remove_check_constraint :hotel_corporate_accounts, name: "hotel_corporate_accounts_account_type_allowed"
    add_check_constraint :hotel_corporate_accounts,
      "account_type IN ('company', 'government', 'travel_agent', 'airline', 'salesperson')",
      name: "hotel_corporate_accounts_account_type_allowed"

    remove_check_constraint :booking_billing_parties, name: "booking_billing_parties_account_type_allowed"
    add_check_constraint :booking_billing_parties,
      "account_type IS NULL OR (account_type::text = ANY (ARRAY['company', 'government', 'travel_agent', 'airline', 'salesperson']::text[]))",
      name: "booking_billing_parties_account_type_allowed"
  end

  def down
    remove_check_constraint :hotel_corporate_accounts, name: "hotel_corporate_accounts_account_type_allowed"
    add_check_constraint :hotel_corporate_accounts,
      "account_type IN ('company', 'government', 'travel_agent', 'airline')",
      name: "hotel_corporate_accounts_account_type_allowed"

    remove_check_constraint :booking_billing_parties, name: "booking_billing_parties_account_type_allowed"
    add_check_constraint :booking_billing_parties,
      "account_type IS NULL OR (account_type::text = ANY (ARRAY['company', 'government', 'travel_agent', 'airline']::text[]))",
      name: "booking_billing_parties_account_type_allowed"
  end
end
