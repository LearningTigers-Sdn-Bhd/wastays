# frozen_string_literal: true

class AddBookingGuestIdToGuestRegistrationCards < ActiveRecord::Migration[8.0]
  def up
    unless column_exists?(:guest_registration_cards, :booking_guest_id)
      add_reference :guest_registration_cards, :booking_guest, foreign_key: true, null: true, index: { unique: true }
    end

    remove_index :guest_registration_cards, :booking_id, if_exists: true
    add_index :guest_registration_cards, :booking_id, if_not_exists: true

    execute <<~SQL
      UPDATE guest_registration_cards grc
      SET booking_guest_id = bg.id
      FROM booking_guests bg
      WHERE bg.booking_id = grc.booking_id AND bg.role = 'primary' AND grc.booking_guest_id IS NULL;
    SQL
  end

  def down
    remove_reference :guest_registration_cards, :booking_guest, foreign_key: true if column_exists?(:guest_registration_cards, :booking_guest_id)
    remove_index :guest_registration_cards, :booking_id, if_exists: true
    add_index :guest_registration_cards, :booking_id, unique: true
  end
end
