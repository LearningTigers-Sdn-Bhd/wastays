# frozen_string_literal: true

class CreateBookingBillingParties < ActiveRecord::Migration[8.0]
  def up
    create_table :booking_billing_parties do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :booking, null: false, foreign_key: true
      t.string :party_kind, null: false
      t.references :booking_guest, foreign_key: true
      t.references :hotel_corporate_account, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.datetime :archived_at

      t.timestamps
    end

    add_check_constraint :booking_billing_parties,
      "party_kind IN ('guest', 'company')",
      name: "booking_billing_parties_kind_allowed"
    add_check_constraint :booking_billing_parties,
      "((booking_guest_id IS NOT NULL)::integer + (hotel_corporate_account_id IS NOT NULL)::integer) = 1",
      name: "booking_billing_parties_one_identity"

    add_index :booking_billing_parties,
      :booking_guest_id,
      unique: true,
      where: "booking_guest_id IS NOT NULL",
      name: "idx_booking_billing_parties_unique_guest"
    add_index :booking_billing_parties,
      [ :booking_id, :hotel_corporate_account_id ],
      unique: true,
      where: "hotel_corporate_account_id IS NOT NULL",
      name: "idx_booking_billing_parties_unique_company"
    add_index :booking_billing_parties, [ :booking_id, :party_kind ]
    add_index :booking_billing_parties, [ :hotel_id, :archived_at ]

    add_reference :booking_folios, :booking_billing_party, foreign_key: true

    backfill_existing_billing_parties
  end

  def down
    remove_reference :booking_folios, :booking_billing_party, foreign_key: true
    drop_table :booking_billing_parties
  end

  private

  def backfill_existing_billing_parties
    execute <<~SQL.squish
      INSERT INTO booking_billing_parties (
        hotel_id,
        booking_id,
        party_kind,
        booking_guest_id,
        created_at,
        updated_at
      )
      SELECT
        bookings.hotel_id,
        booking_guests.booking_id,
        'guest',
        booking_guests.id,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM booking_guests
      INNER JOIN bookings ON bookings.id = booking_guests.booking_id
      ON CONFLICT DO NOTHING
    SQL

    execute <<~SQL.squish
      INSERT INTO booking_billing_parties (
        hotel_id,
        booking_id,
        party_kind,
        hotel_corporate_account_id,
        created_at,
        updated_at
      )
      SELECT DISTINCT
        booking_folios.hotel_id,
        booking_folios.booking_id,
        'company',
        booking_folios.hotel_corporate_account_id,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM booking_folios
      WHERE booking_folios.payer_type = 'company'
        AND booking_folios.hotel_corporate_account_id IS NOT NULL
      ON CONFLICT DO NOTHING
    SQL

    execute <<~SQL.squish
      UPDATE booking_folios
      SET booking_billing_party_id = booking_billing_parties.id
      FROM booking_billing_parties
      WHERE booking_folios.booking_billing_party_id IS NULL
        AND booking_folios.payer_type = 'company'
        AND booking_folios.hotel_corporate_account_id IS NOT NULL
        AND booking_billing_parties.booking_id = booking_folios.booking_id
        AND booking_billing_parties.hotel_corporate_account_id = booking_folios.hotel_corporate_account_id
    SQL

    execute <<~SQL.squish
      UPDATE booking_folios
      SET booking_billing_party_id = guest_parties.booking_billing_party_id
      FROM (
        SELECT
          booking_guests.booking_id,
          MIN(booking_billing_parties.id) AS booking_billing_party_id,
          COUNT(*) AS guest_count
        FROM booking_guests
        INNER JOIN booking_billing_parties ON booking_billing_parties.booking_guest_id = booking_guests.id
        GROUP BY booking_guests.booking_id
      ) guest_parties
      WHERE booking_folios.booking_billing_party_id IS NULL
        AND booking_folios.payer_type = 'guest'
        AND guest_parties.guest_count = 1
        AND guest_parties.booking_id = booking_folios.booking_id
    SQL
  end
end
