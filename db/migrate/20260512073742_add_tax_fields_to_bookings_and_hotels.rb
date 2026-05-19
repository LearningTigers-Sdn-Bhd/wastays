class AddTaxFieldsToBookingsAndHotels < ActiveRecord::Migration[8.0]
  def change
    add_column :bookings, :tax_lines, :jsonb, default: [], null: false
    add_column :hotels, :sst_enabled, :boolean, default: false, null: false
  end
end
