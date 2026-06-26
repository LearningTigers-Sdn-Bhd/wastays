# frozen_string_literal: true

class RemoveCorporateTypeFromHotelCorporateAccounts < ActiveRecord::Migration[8.0]
  def change
    remove_column :hotel_corporate_accounts, :corporate_type, :string
  end
end
