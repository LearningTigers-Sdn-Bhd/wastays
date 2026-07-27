# frozen_string_literal: true

class ScopeDepositReferencesToOwner < ActiveRecord::Migration[8.0]
  def change
    remove_index :deposits, name: "index_deposits_on_hotel_id_and_external_reference", if_exists: true

    add_index :deposits, [ :hotel_id, :booking_id, :external_reference ], unique: true,
      where: "booking_id IS NOT NULL AND external_reference IS NOT NULL",
      name: "idx_deposits_booking_reference", if_not_exists: true
    add_index :deposits, [ :hotel_id, :group_booking_id, :external_reference ], unique: true,
      where: "group_booking_id IS NOT NULL AND external_reference IS NOT NULL",
      name: "idx_deposits_group_reference", if_not_exists: true
  end
end
