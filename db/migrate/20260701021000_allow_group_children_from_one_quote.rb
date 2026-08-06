# frozen_string_literal: true

class AllowGroupChildrenFromOneQuote < ActiveRecord::Migration[8.0]
  def change
    remove_index :bookings, name: "index_bookings_on_booking_quote_id_unique"
    add_index :bookings, :booking_quote_id, name: "index_bookings_on_booking_quote_id"
  end
end
