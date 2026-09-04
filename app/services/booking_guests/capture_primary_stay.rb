# frozen_string_literal: true

module BookingGuests
  class CapturePrimaryStay
    def self.call(booking_guest:)
      booking = booking_guest.booking
      booking_guest.update!(
        name_snapshot: booking.guest_name,
        email_snapshot: booking.guest_email,
        phone_snapshot: booking.guest_phone,
        country_snapshot: booking.guest_country,
        city_snapshot: booking.guest_city,
        state_code_snapshot: booking.guest_state_code,
        postal_code_snapshot: booking.guest_postal_code,
        address_country_snapshot: booking.guest_address_country,
        gender_snapshot: booking.guest_gender,
        document_type_snapshot: booking.guest_document_type,
        government_id_snapshot: booking.guest_government_id,
        date_of_birth_snapshot: booking.guest_date_of_birth,
        home_address_snapshot: booking.guest_home_address
      )
    end
  end
end
