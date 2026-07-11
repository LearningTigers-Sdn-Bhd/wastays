# frozen_string_literal: true

class BackfillMissingPrimaryBookingGuests < ActiveRecord::Migration[8.0]
  class MigrationBooking < ActiveRecord::Base
    self.table_name = "bookings"
  end

  class MigrationBookingGuest < ActiveRecord::Base
    self.table_name = "booking_guests"
  end

  class MigrationGuest < ActiveRecord::Base
    self.table_name = "guests"
  end

  def up
    missing_primary_booking_ids.find_each do |booking|
      existing_link = MigrationBookingGuest.where(booking_id: booking.id).order(:created_at, :id).first
      if existing_link
        existing_link.update!(is_primary: true, role: "primary")
        next
      end

      guest = MigrationGuest.create!(
        name: booking.guest_name,
        email: booking.guest_email,
        phone: booking.guest_phone,
        gender: booking.guest_gender,
        country: booking.guest_country,
        document_type: booking.guest_document_type,
        metadata: {},
        created_at: Time.current,
        updated_at: Time.current
      )
      MigrationBookingGuest.create!(
        booking_id: booking.id,
        guest_id: guest.id,
        is_primary: true,
        role: "primary",
        name_snapshot: booking.guest_name,
        email_snapshot: booking.guest_email,
        phone_snapshot: booking.guest_phone,
        gender_snapshot: booking.guest_gender,
        country_snapshot: booking.guest_country,
        document_type_snapshot: booking.guest_document_type,
        created_at: Time.current,
        updated_at: Time.current
      )
    end
  end

  def down
    # Snapshot-backed guest links are retained because deleting guest identity is unsafe.
  end

  private

  def missing_primary_booking_ids
    MigrationBooking.where.not(status: "pending")
      .where.not(id: MigrationBookingGuest.where(role: "primary").select(:booking_id))
  end
end
