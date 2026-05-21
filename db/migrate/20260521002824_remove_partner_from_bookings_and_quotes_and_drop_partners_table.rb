class RemovePartnerFromBookingsAndQuotesAndDropPartnersTable < ActiveRecord::Migration[8.0]
  def change
    remove_reference :bookings, :partner, foreign_key: true
    remove_reference :booking_quotes, :partner, foreign_key: true

    drop_table :partners do |t|
      t.references :hotel, null: false, foreign_key: true
      t.string :name, null: false
      t.string :code, null: false
      t.string :domain
      t.timestamps
    end
  end
end
