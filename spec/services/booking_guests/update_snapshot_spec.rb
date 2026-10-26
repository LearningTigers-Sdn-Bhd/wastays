# frozen_string_literal: true

require "rails_helper"

RSpec.describe BookingGuests::UpdateSnapshot do
  let(:booking_guest) { create(:booking_guest, is_primary: true) }
  let(:booking) { booking_guest.booking }
  let(:guest) { booking_guest.guest }
  let(:actor) { create(:user) }
  let(:attributes) do
    {
      name: "Stay Name",
      email: "stay@example.com",
      phone: "+60128889999",
      country: "Malaysia",
      gender: "female",
      document_type: "passport",
      government_id: "P9988",
      date_of_birth: "1992-03-04",
      home_address: "No. 12, Jalan Ampang",
      city: "Kuala Lumpur",
      state_code: "14",
      postal_code: "50450",
      address_country: "Malaysia"
    }
  end

  it "updates the stay snapshot and primary booking fields without changing the guest profile" do
    original_profile_name = guest.name
    original_profile_address = guest.home_address

    result = described_class.call(booking_guest:, attributes:, actor:)

    expect(result).to be_success
    expect(booking_guest.reload).to have_attributes(
      name_snapshot: "Stay Name",
      government_id_snapshot: "p9988",
      date_of_birth_snapshot: Date.new(1992, 3, 4),
      home_address_snapshot: "No. 12, Jalan Ampang",
      city_snapshot: "Kuala Lumpur",
      state_code_snapshot: "14",
      postal_code_snapshot: "50450",
      address_country_snapshot: "Malaysia"
    )
    expect(booking.reload).to have_attributes(
      guest_name: "Stay Name",
      guest_email: "stay@example.com",
      guest_home_address: "No. 12, Jalan Ampang",
      guest_city: "Kuala Lumpur",
      guest_state_code: "14",
      guest_postal_code: "50450",
      guest_address_country: "Malaysia"
    )
    expect(guest.reload.name).to eq(original_profile_name)
    expect(guest.reload.home_address).to eq(original_profile_address)
  end

  it "saves the primary guest with a blank phone" do
    result = described_class.call(booking_guest:, attributes: attributes.merge(phone: ""), actor:)

    expect(result).to be_success
    expect(booking.reload.guest_phone).to be_blank
  end

  it "updates the reusable guest profile only when requested" do
    guest.update!(name: "Stay Nam", document_type: "passport", government_id: "P9988")

    result = described_class.call(booking_guest:, attributes:, actor:, update_profile: true)

    expect(result).to be_success
    expect(booking_guest.reload.name_snapshot).to eq("Stay Name")
    expect(guest.reload).to have_attributes(
      name: "Stay Name",
      date_of_birth: Date.new(1992, 3, 4),
      home_address: "No. 12, Jalan Ampang",
      city: "Kuala Lumpur",
      state_code: "14",
      postal_code: "50450",
      address_country: "Malaysia"
    )
  end

  it "refuses to save another person's details over the guest record" do
    guest.update!(name: "Hendry Lepizus Datu", document_type: "passport", government_id: "A1234567")

    result = described_class.call(booking_guest:, attributes: attributes.merge(name: "Ruben Bin Tinting"), actor:, update_profile: true)

    expect(result).not_to be_success
    expect(result.errors.first).to include("Hendry Lepizus Datu's guest record was not changed")
    expect(guest.reload).to have_attributes(name: "Hendry Lepizus Datu", government_id: "a1234567")
    expect(booking_guest.reload.name_snapshot).not_to eq("Ruben Bin Tinting")
  end

  it "still saves another person's details to the stay only" do
    guest.update!(name: "Hendry Lepizus Datu")

    result = described_class.call(booking_guest:, attributes: attributes.merge(name: "Ruben Bin Tinting"), actor:)

    expect(result).to be_success
    expect(booking_guest.reload.name_snapshot).to eq("Ruben Bin Tinting")
    expect(guest.reload.name).to eq("Hendry Lepizus Datu")
  end

  it "does not partially update any layer when validation fails" do
    original_snapshot = booking_guest.name_snapshot
    original_booking_name = booking.guest_name
    original_profile_name = guest.name

    result = described_class.call(booking_guest:, attributes: attributes.merge(name: ""), actor:, update_profile: true)

    expect(result).not_to be_success
    expect(booking_guest.reload.name_snapshot).to eq(original_snapshot)
    expect(booking.reload.guest_name).to eq(original_booking_name)
    expect(guest.reload.name).to eq(original_profile_name)
  end
end
