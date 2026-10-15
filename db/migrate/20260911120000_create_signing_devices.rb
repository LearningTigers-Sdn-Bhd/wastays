# frozen_string_literal: true

# A tablet parked at the front desk, waiting to be handed a registration card.
#
# The device holds a token rather than a staff session. Staff sign in once to
# enrol the tablet and are dropped immediately after, so a tablet left on the
# counter can receive cards to sign but cannot reach the rest of the portal.
#
# `current_booking_id` is the stay the device is working through. It is the
# whole of the queue: the next card is whichever of that booking's guests has
# not signed yet, so an abandoned signature resumes rather than restarts, and
# clearing it returns the tablet to its idle screen.
class CreateSigningDevices < ActiveRecord::Migration[8.0]
  def change
    create_table :signing_devices do |t|
      t.references :hotel, null: false, foreign_key: true
      t.string :public_token, null: false
      t.string :label, null: false

      # Nullable: a device with no stay in hand is idle, which is its resting
      # state. Nullified rather than restricted, so voiding a booking cannot
      # leave a tablet pointing at a stay that no longer exists.
      t.references :current_booking, null: true, foreign_key: { to_table: :bookings, on_delete: :nullify }

      t.datetime :last_seen_at

      t.timestamps
    end

    add_index :signing_devices, :public_token, unique: true
  end
end
