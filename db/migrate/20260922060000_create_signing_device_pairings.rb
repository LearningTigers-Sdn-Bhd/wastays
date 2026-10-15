# frozen_string_literal: true

# A short-lived invitation for a tablet to become a signing device.
#
# Enrolment used to mean signing a staff member in on the tablet and then
# destroying that session. It worked, but it put real portal credentials on a
# device that lives on a counter, and it needed someone to type a URL from
# memory. A pairing replaces both: the desk mints one, the tablet scans it or
# types its code, and the tablet never sees a login screen.
#
# The trade is that for as long as a pairing is live, whoever holds the code can
# enrol a tablet at this property. That is bounded rather than eliminated --
# short expiry, single use, and a code with enough entropy that guessing it is
# not the easy way in.
class CreateSigningDevicePairings < ActiveRecord::Migration[8.1]
  def change
    create_table :signing_device_pairings do |t|
      t.references :hotel, null: false, foreign_key: true

      # The long random in the QR, and the short one a person can read off a
      # screen and type. Two ways into the same pairing, so a tablet with no
      # working camera is not locked out.
      t.string :token, null: false
      t.string :code, null: false

      t.datetime :expires_at, null: false

      # Set the moment a tablet claims it. A pairing is single use: this is what
      # makes a QR left open on a screen worthless after the first tablet.
      t.datetime :claimed_at

      # Who minted it and what it became, kept after the fact -- pairing a
      # device is the one moment a tablet gains access to guest data, and it
      # should be answerable later.
      t.references :created_by_user, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :signing_device, null: true, foreign_key: { on_delete: :nullify }

      t.timestamps
    end

    add_index :signing_device_pairings, :token, unique: true
    add_index :signing_device_pairings, :code, unique: true
    # The sweep that keeps a property's stale pairings from piling up.
    add_index :signing_device_pairings, [ :hotel_id, :claimed_at, :expires_at ],
              name: "index_signing_device_pairings_on_hotel_and_state"
  end
end
