class AddTourismTaxCollectedToBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :bookings, :tourism_tax_collected, :boolean, default: false, null: false
  end
end
