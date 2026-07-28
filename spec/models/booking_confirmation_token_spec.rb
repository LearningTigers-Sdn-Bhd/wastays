# frozen_string_literal: true

require "rails_helper"

RSpec.describe BookingConfirmationToken do
  it "registers booking and group tokens in one global namespace" do
    booking = create(:booking)
    group = create(:group_booking)

    expect(booking.booking_confirmation_token.token).to eq(booking.confirmation_token)
    expect(group.booking_confirmation_token.token).to eq(group.confirmation_token)
    expect(described_class.where(token: [ booking.confirmation_token, group.confirmation_token ]).count).to eq(2)
  end

  it "keeps the shared token synchronized when a legacy token changes" do
    booking = create(:booking)

    booking.update!(confirmation_token: "ABC234")

    expect(booking.reload.booking_confirmation_token.token).to eq("ABC234")
  end

  it "requires exactly one owner" do
    token = described_class.new(token: "ABC234")

    expect(token).not_to be_valid
    expect(token.errors[:base]).to include("Confirmation token must belong to exactly one booking or group booking")
  end
end
