# frozen_string_literal: true

class CreateHotelTransactionConfigurations < ActiveRecord::Migration[8.0]
  def change
    create_table :hotel_transaction_configurations do |t|
      t.references :hotel, null: false, foreign_key: true, index: { unique: true }
      t.boolean :apply_room_revenue_tax_rules_to_new_bookings, null: false, default: false

      t.timestamps
    end
  end
end
