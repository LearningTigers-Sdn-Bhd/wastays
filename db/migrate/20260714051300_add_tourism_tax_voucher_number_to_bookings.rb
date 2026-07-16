# frozen_string_literal: true

class AddTourismTaxVoucherNumberToBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :bookings, :tourism_tax_voucher_number, :integer
    add_index :bookings, [ :hotel_id, :tourism_tax_voucher_number ], unique: true,
      where: "tourism_tax_voucher_number IS NOT NULL", name: "idx_bookings_on_hotel_tourism_tax_voucher_number"
  end
end
