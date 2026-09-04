# frozen_string_literal: true

class AddBillingAddressToHotelCorporateAccounts < ActiveRecord::Migration[8.0]
  def change
    change_table :hotel_corporate_accounts, bulk: true do |t|
      t.string :billing_address_line1
      t.string :billing_address_line2
      t.string :billing_city
      t.string :billing_state
      t.string :billing_postal_code
      t.string :billing_country
    end
  end
end
