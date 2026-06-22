class AddMissingFundCollectorToBookings < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:bookings, :fund_collector)
      add_column :bookings, :fund_collector, :string, default: "unknown", null: false
    end

    add_index :bookings, :fund_collector unless index_exists?(:bookings, :fund_collector)
  end
end
