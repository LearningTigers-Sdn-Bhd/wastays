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
      home_address: "No. 12, Jalan Ampang"
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
      home_address_snapshot: "No. 12, Jalan Ampang"
    )
    expect(booking.reload).to have_attributes(guest_name: "Stay Name", guest_email: "stay@example.com", guest_home_address: "No. 12, Jalan Ampang")
    expect(guest.reload.name).to eq(original_profile_name)
    expect(guest.reload.home_address).to eq(original_profile_address)
  end

  it "updates the reusable guest profile only when requested" do
    result = described_class.call(booking_guest:, attributes:, actor:, update_profile: true)

    expect(result).to be_success
    expect(booking_guest.reload.name_snapshot).to eq("Stay Name")
    expect(guest.reload).to have_attributes(name: "Stay Name", date_of_birth: Date.new(1992, 3, 4), home_address: "No. 12, Jalan Ampang")
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
