# frozen_string_literal: true

class AddFundCollectorToBookings < ActiveRecord::Migration[8.1]
  def change
    add_column :bookings, :fund_collector, :string, null: false, default: "unknown"
    add_index :bookings, :fund_collector
  end
end
