# frozen_string_literal: true

# A booking already knows the agency it belongs to (hotel_corporate_account_id),
# but not which person at that agency made it. That is the half staff ask about
# when they ring the agency back, and it cannot be reconstructed afterwards --
# so it is recorded from now on rather than backfilled later.
class AddCorporateBookedByToBookings < ActiveRecord::Migration[8.1]
  def change
    add_reference :bookings, :corporate_booked_by, null: true, foreign_key: { to_table: :users }, index: true
    add_column :bookings, :corporate_booked_at, :datetime, null: true
  end
end
