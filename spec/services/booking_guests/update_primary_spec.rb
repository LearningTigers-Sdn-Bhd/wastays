# frozen_string_literal: true

require "rails_helper"

RSpec.describe BookingGuests::UpdatePrimary do
  let(:booking) { create(:booking, guest_country: "Malaysia") }
  let(:actor) { create(:user) }
  let(:attributes) do
    {
      name: "Updated Primary",
      email: "primary@example.com",
      phone: "123456",
      country: "Malaysia",
      document_type: "passport",
      government_id: "P123",
      date_of_birth: "1990-01-02"
    }
  end

  before { booking.booking_guests.destroy_all }

  it "creates and updates the missing primary guest atomically" do
    result = described_class.call(booking:, attributes:, actor:)

    expect(result).to be_success
    expect(booking.reload).to have_attributes(guest_name: "Updated Primary", guest_email: "primary@example.com")
    expect(booking.primary_guest).to have_attributes(name: "Updated Primary", government_id: "p123")
  end

  it "reports a BIBO validation rollback as a failure" do
    result = described_class.call(
      booking:,
      attributes:,
      actor:,
      bibo_attributes: { boat_in_at: 2.days.from_now, boat_out_at: 1.day.from_now }
    )

    expect(result).not_to be_success
    expect(result.errors).to include("Boat out at must be after boat in time")
    expect(booking.reload.guest_name).not_to eq("Updated Primary")
  end
end
