# frozen_string_literal: true

class AddChargeTypeToHotelTaxes < ActiveRecord::Migration[8.0]
  def change
    add_column :hotel_taxes, :charge_type, :string, null: false, default: "tax"
  end
end
