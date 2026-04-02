class AddGuestFieldsToBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :bookings, :guest_gender, :string
    add_column :bookings, :guest_country, :string
    add_column :bookings, :guest_document_type, :string
    add_column :bookings, :tourism_tax_amount, :decimal, precision: 10, scale: 2, default: 0.0, null: false
    add_column :bookings, :tourism_tax_applied, :boolean, default: false, null: false
  end
end
