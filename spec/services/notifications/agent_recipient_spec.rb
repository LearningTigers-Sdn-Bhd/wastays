# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::AgentRecipient do
  let(:hotel) { create(:hotel, status: "live") }
  let(:corporate_user) { create(:user, :corporate) }
  let(:relationship) do
    create(:hotel_corporate_account, hotel: hotel, corporate_account: corporate_user.account,
                                     account_type: "travel_agent", contact_email: "desk@agency.test")
  end
  let(:booking) { create(:booking, hotel: hotel, hotel_corporate_account: relationship) }

  it "writes to the person who made the booking" do
    booking.update!(corporate_booked_by: corporate_user)

    expect(described_class.email_for(booking)).to eq(corporate_user.email)
    expect(described_class.name_for(booking)).to eq(corporate_user.name)
  end

  # Bookings made before corporate_booked_by was recorded have no person, and
  # neither does one made by somebody who has since left the agency.
  it "falls back to the account's contact address when nobody is named" do
    expect(described_class.email_for(booking)).to eq("desk@agency.test")
    expect(described_class.name_for(booking)).to eq(relationship.corporate_account.name)
  end

  it "returns nil rather than raising when there is nowhere to write" do
    plain = create(:booking, hotel: hotel)

    expect(described_class.email_for(plain)).to be_nil
  end
end
