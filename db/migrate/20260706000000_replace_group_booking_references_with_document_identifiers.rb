# frozen_string_literal: true

class ReplaceGroupBookingReferencesWithDocumentIdentifiers < ActiveRecord::Migration[8.0]
  class MigrationHotelCounter < ApplicationRecord
    self.table_name = "hotel_counters"
  end

  class MigrationGroupBooking < ApplicationRecord
    self.table_name = "group_bookings"
  end

  TOKEN_CHARSET = (("A".."Z").to_a + ("2".."9").to_a - %w[I O L]).freeze
  TOKEN_LENGTH = 6

  def up
    add_column :group_bookings, :confirmation_token, :string
    add_column :group_bookings, :reservation_number, :integer
    add_column :group_bookings, :receipt_number, :integer

    backfill_group_booking_identifiers!

    change_column_null :group_bookings, :confirmation_token, false
    change_column_null :group_bookings, :reservation_number, false
    change_column_null :group_bookings, :receipt_number, false

    remove_index :group_bookings, [ :hotel_id, :reference ]
    remove_column :group_bookings, :reference

    add_index :group_bookings, :confirmation_token, unique: true
    add_index :group_bookings, [ :hotel_id, :reservation_number ], unique: true, name: "idx_group_bookings_on_hotel_reservation_number"
    add_index :group_bookings, [ :hotel_id, :receipt_number ], unique: true, name: "idx_group_bookings_on_hotel_receipt_number"
    add_index :bookings, [ :hotel_id, :reservation_number ], unique: true, where: "reservation_number IS NOT NULL", name: "idx_bookings_on_hotel_reservation_number"
    add_index :bookings, [ :hotel_id, :receipt_number ], unique: true, where: "receipt_number IS NOT NULL", name: "idx_bookings_on_hotel_receipt_number"
  end

  def down
    add_column :group_bookings, :reference, :string
    MigrationGroupBooking.reset_column_information
    MigrationGroupBooking.find_each do |group_booking|
      group_booking.update_columns(reference: "GRP-#{group_booking.confirmation_token}")
    end
    change_column_null :group_bookings, :reference, false

    remove_index :bookings, name: "idx_bookings_on_hotel_receipt_number"
    remove_index :bookings, name: "idx_bookings_on_hotel_reservation_number"
    remove_index :group_bookings, name: "idx_group_bookings_on_hotel_receipt_number"
    remove_index :group_bookings, name: "idx_group_bookings_on_hotel_reservation_number"
    remove_index :group_bookings, name: "index_group_bookings_on_confirmation_token"
    remove_column :group_bookings, :receipt_number
    remove_column :group_bookings, :reservation_number
    remove_column :group_bookings, :confirmation_token
    add_index :group_bookings, [ :hotel_id, :reference ], unique: true
  end

  private

  def backfill_group_booking_identifiers!
    MigrationGroupBooking.reset_column_information
    MigrationGroupBooking.find_each do |group_booking|
      group_booking.update_columns(
        confirmation_token: next_token,
        reservation_number: increment_counter!(group_booking.hotel_id, "reservation"),
        receipt_number: increment_counter!(group_booking.hotel_id, "receipt")
      )
    end
  end

  def next_token
    loop do
      candidate = Array.new(TOKEN_LENGTH) { TOKEN_CHARSET.sample }.join
      return candidate unless MigrationGroupBooking.exists?(confirmation_token: candidate)
    end
  end

  def increment_counter!(hotel_id, counter_type)
    counter = MigrationHotelCounter.find_or_create_by!(hotel_id: hotel_id, counter_type: counter_type)
    counter.with_lock { counter.increment!(:last_value) }
    counter.last_value
  end
end
