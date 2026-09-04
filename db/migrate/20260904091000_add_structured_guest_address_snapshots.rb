# frozen_string_literal: true

class AddStructuredGuestAddressSnapshots < ActiveRecord::Migration[8.0]
  def change
    add_column :guests, :address_country, :string
    add_column :bookings, :guest_address_country, :string

    change_table :booking_guests, bulk: true do |t|
      t.string :city_snapshot
      t.string :state_code_snapshot
      t.string :postal_code_snapshot
      t.string :address_country_snapshot
    end

    add_column :e_invoice_submissions, :buyer_snapshot, :jsonb, default: {}, null: false
  end
end
