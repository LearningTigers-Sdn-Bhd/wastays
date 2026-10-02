# frozen_string_literal: true

class AddChargeChildrenToHotelExtraCharges < ActiveRecord::Migration[8.1]
  def change
    add_column :hotel_extra_charges, :charge_children, :boolean, default: true, null: false
  end
end
