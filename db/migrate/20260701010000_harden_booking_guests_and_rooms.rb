# frozen_string_literal: true

class HardenBookingGuestsAndRooms < ActiveRecord::Migration[8.0]
  def up
    duplicate_links = select_value(<<~SQL.squish).to_i
      SELECT COUNT(*) FROM (
        SELECT booking_id, guest_id
        FROM booking_guests
        GROUP BY booking_id, guest_id
        HAVING COUNT(*) > 1
      ) duplicates
    SQL
    duplicate_primaries = select_value(<<~SQL.squish).to_i
      SELECT COUNT(*) FROM (
        SELECT booking_id
        FROM booking_guests
        WHERE is_primary = TRUE
        GROUP BY booking_id
        HAVING COUNT(*) > 1
      ) duplicates
    SQL
    if duplicate_links.positive? || duplicate_primaries.positive?
      raise ActiveRecord::MigrationError,
        "Booking guest cleanup required before migration: #{duplicate_links} duplicate links, #{duplicate_primaries} duplicate primary sets"
    end

    add_column :booking_guests, :role, :string, null: false, default: "additional"
    add_column :booking_guests, :name_snapshot, :string
    add_column :booking_guests, :email_snapshot, :string
    add_column :booking_guests, :phone_snapshot, :string
    add_column :booking_guests, :government_id_snapshot, :string
    add_column :booking_guests, :gender_snapshot, :string
    add_column :booking_guests, :country_snapshot, :string
    add_column :booking_guests, :document_type_snapshot, :string

    execute <<~SQL.squish
      UPDATE booking_guests
      SET role = CASE WHEN is_primary = TRUE THEN 'primary' ELSE 'additional' END
    SQL

    execute <<~SQL.squish
      UPDATE booking_guests
      SET name_snapshot = guests.name,
          email_snapshot = guests.email,
          phone_snapshot = guests.phone,
          government_id_snapshot = guests.government_id,
          gender_snapshot = guests.gender,
          country_snapshot = guests.country,
          document_type_snapshot = guests.document_type
      FROM guests
      WHERE guests.id = booking_guests.guest_id
    SQL

    add_index :booking_guests, [ :booking_id, :guest_id ], unique: true
    add_index :booking_guests,
      :booking_id,
      unique: true,
      where: "role = 'primary'",
      name: "idx_booking_guests_one_primary_per_booking"
    add_check_constraint :booking_guests,
      "role IN ('primary', 'additional')",
      name: "booking_guests_role_allowed"
  end

  def down
    remove_check_constraint :booking_guests, name: "booking_guests_role_allowed"
    remove_index :booking_guests, name: "idx_booking_guests_one_primary_per_booking"
    remove_index :booking_guests, column: [ :booking_id, :guest_id ]

    %i[
      role name_snapshot email_snapshot phone_snapshot government_id_snapshot
      gender_snapshot country_snapshot document_type_snapshot
    ].each { |column| remove_column :booking_guests, column }
  end
end
