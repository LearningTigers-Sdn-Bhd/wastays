# frozen_string_literal: true

require "rails_helper"

RSpec.describe BookingGuests::CapturePrimaryStay do
  let(:booking) do
    create(
      :booking,
      guest_name: "Aisha Tan",
      guest_email: "aisha.tan@example.com",
      guest_phone: "+60123456789",
      guest_country: "Malaysia",
      guest_gender: "female",
      guest_document_type: "ic",
      guest_government_id: "900101-10-1234",
      guest_date_of_birth: Date.new(1990, 1, 1),
      guest_home_address: "No. 12, Jalan Ampang",
      guest_city: "Kuala Lumpur",
      guest_state_code: "14",
      guest_postal_code: "50450",
      guest_address_country: "Malaysia"
    )
  end
  let(:booking_guest) { create(:booking_guest, booking: booking, is_primary: true) }

  it "copies every stay detail from the booking onto the primary guest" do
    described_class.call(booking_guest: booking_guest)

    expect(booking_guest.reload).to have_attributes(
      name_snapshot: "Aisha Tan",
      email_snapshot: "aisha.tan@example.com",
      phone_snapshot: "+60123456789",
      country_snapshot: "Malaysia",
      gender_snapshot: "female",
      document_type_snapshot: "ic",
      government_id_snapshot: "900101-10-1234",
      date_of_birth_snapshot: Date.new(1990, 1, 1),
      home_address_snapshot: "No. 12, Jalan Ampang",
      city_snapshot: "Kuala Lumpur",
      state_code_snapshot: "14",
      postal_code_snapshot: "50450",
      address_country_snapshot: "Malaysia"
    )
  end

  # The snapshot is what the registration card and the e-invoice read, so a later
  # booking edit must reach it rather than leaving the old address in place.
  it "overwrites an earlier snapshot with the booking's current details" do
    booking_guest.update!(city_snapshot: "Ipoh", state_code_snapshot: "08", address_country_snapshot: "Malaysia")
    booking.update!(guest_city: "Kota Kinabalu", guest_state_code: "12", guest_address_country: "Malaysia")

    described_class.call(booking_guest: booking_guest.reload)

    expect(booking_guest.reload).to have_attributes(
      city_snapshot: "Kota Kinabalu",
      state_code_snapshot: "12",
      address_country_snapshot: "Malaysia"
    )
  end

  it "clears a snapshot field the booking no longer carries" do
    booking_guest.update!(postal_code_snapshot: "50450")
    booking.update!(guest_postal_code: nil)

    described_class.call(booking_guest: booking_guest.reload)

    expect(booking_guest.reload.postal_code_snapshot).to be_nil
  end
end
