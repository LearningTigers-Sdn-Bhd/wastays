# frozen_string_literal: true

class AddAutoApplyToHotelExtraCharges < ActiveRecord::Migration[8.1]
  def change
    add_column :hotel_extra_charges, :auto_apply, :boolean, default: false, null: false
  end
end
