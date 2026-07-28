# frozen_string_literal: true

require "rails_helper"

RSpec.describe DocumentIdentifiers::SyncConfirmationToken do
  it "updates the registered token to match its booking" do
    booking = create(:booking)
    booking.update_column(:confirmation_token, "SYNC1234")

    described_class.call!(record: booking)

    expect(booking.booking_confirmation_token.reload.token).to eq("SYNC1234")
  end
end
