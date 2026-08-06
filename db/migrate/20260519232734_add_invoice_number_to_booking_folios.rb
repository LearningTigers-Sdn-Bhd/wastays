class AddInvoiceNumberToBookingFolios < ActiveRecord::Migration[8.0]
  def change
    add_column :booking_folios, :invoice_number, :integer
    add_index :booking_folios, [ :hotel_id, :invoice_number ], unique: true, where: "invoice_number IS NOT NULL"
  end
end
