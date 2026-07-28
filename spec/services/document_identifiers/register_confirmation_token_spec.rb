# frozen_string_literal: true

require "rails_helper"

RSpec.describe DocumentIdentifiers::RegisterConfirmationToken do
  it "registers a booking confirmation token with its owner" do
    booking = create(:booking)
    booking.booking_confirmation_token.destroy!

    described_class.call!(record: booking)

    expect(booking.reload.booking_confirmation_token).to have_attributes(token: booking.confirmation_token)
  end
end
