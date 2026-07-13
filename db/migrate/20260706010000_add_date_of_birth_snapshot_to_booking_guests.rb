class AddDateOfBirthSnapshotToBookingGuests < ActiveRecord::Migration[8.0]
  def change
    add_column :booking_guests, :date_of_birth_snapshot, :date
  end
end
