# frozen_string_literal: true

class AddAgentFieldsToHotelCorporateAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :hotel_corporate_accounts, :agent_code, :string
    add_column :hotel_corporate_accounts, :contact_email, :string
    add_column :hotel_corporate_accounts, :contact_phone, :string
    add_index :hotel_corporate_accounts, [ :hotel_id, :agent_code ], unique: true

    remove_check_constraint :hotel_corporate_accounts, name: "hotel_corporate_accounts_account_type_allowed"
    add_check_constraint :hotel_corporate_accounts,
      "account_type IN ('company', 'government', 'travel_agent', 'airline')",
      name: "hotel_corporate_accounts_account_type_allowed"
  end
end
