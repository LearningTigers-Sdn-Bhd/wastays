# frozen_string_literal: true

class AddAccountTypeToHotelCorporateAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :hotel_corporate_accounts, :account_type, :string, null: false, default: "company"

    add_check_constraint :hotel_corporate_accounts,
      "account_type IN ('company', 'government', 'travel_agent')",
      name: "hotel_corporate_accounts_account_type_allowed"
  end
end
