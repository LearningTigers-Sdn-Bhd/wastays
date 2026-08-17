# frozen_string_literal: true

class AllowBookingsWithoutGuestEmail < ActiveRecord::Migration[8.1]
  # Distinct from `source`, which records the channel a booking arrived through
  # and is chosen by the operator — a desk booking may legitimately be sourced
  # "agoda". This records how the record was entered, which is what decides
  # whether an email address can be missing.
  def up
    add_column :bookings, :created_by_staff, :boolean, default: false, null: false
    change_column_null :bookings, :guest_email, true
  end

  def down
    # Only safe while every booking still carries an address; the guard makes
    # that explicit rather than failing halfway through the column change.
    if Booking.where(guest_email: nil).exists?
      raise ActiveRecord::IrreversibleMigration,
        "Bookings exist without a guest email; backfill them before restoring the NOT NULL constraint."
    end

    change_column_null :bookings, :guest_email, false
    remove_column :bookings, :created_by_staff
  end
end
