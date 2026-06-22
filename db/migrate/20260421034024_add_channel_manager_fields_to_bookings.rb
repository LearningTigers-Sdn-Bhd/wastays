class AddChannelManagerFieldsToBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :bookings, :source, :string, default: "internal"
    add_column :bookings, :fund_collector, :string, default: "unknown", null: false
    add_column :bookings, :external_reference, :string
    add_column :bookings, :channel_manager_reference, :string
    add_column :bookings, :revision_number, :integer, default: 0

    add_index :bookings, :source
    add_index :bookings, :fund_collector
    add_index :bookings, :external_reference
    add_index :bookings, :channel_manager_reference
  end
end
