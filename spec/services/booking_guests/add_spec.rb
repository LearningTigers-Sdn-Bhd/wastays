# frozen_string_literal: true

require "rails_helper"

RSpec.describe BookingGuests::Add do
  let(:booking) { create(:booking) }
  let(:actor) { create(:user) }
  let(:attributes) do
    {
      name: "Added Guest",
      email: "added@example.com",
      country: "Malaysia",
      document_type: "passport",
      date_of_birth: "1993-04-05"
    }
  end

  it "creates an additional guest and records the audit atomically" do
    result = described_class.call(booking:, attributes:, actor:)

    expect(result).to be_success
    expect(result.guest).to have_attributes(created_by_hotel: booking.hotel, name: "Added Guest")
    expect(result.booking_guest).not_to be_primary
    expect(BookingAuditLog.where(auditable: booking, action_type: "guest_added")).to exist
  end

  it "returns validation errors without creating a booking guest" do
    result = described_class.call(booking:, attributes: attributes.merge(name: ""), actor:)

    expect(result).not_to be_success
    expect(result.errors).to include("Name can't be blank")
    expect(booking.booking_guests).to be_empty
  end
end
