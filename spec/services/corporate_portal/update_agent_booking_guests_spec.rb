# frozen_string_literal: true

require "rails_helper"

RSpec.describe CorporatePortal::UpdateAgentBookingGuests do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, :corporate) }

  describe ".editable?" do
    it "allows a confirmed booking that has not arrived yet" do
      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: hotel.business_date_for + 3, check_out: hotel.business_date_for + 5)

      expect(described_class.editable?(booking)).to be(true)
    end

    it "refuses a booking that is checked in, cancelled or already past arrival" do
      checked_in = create(:booking, hotel: hotel, status: "checked_in", check_in: hotel.business_date_for + 3, check_out: hotel.business_date_for + 5)
      past = create(:booking, hotel: hotel, status: "confirmed", check_in: hotel.business_date_for - 2, check_out: hotel.business_date_for + 1)

      expect(described_class.editable?(checked_in)).to be(false)
      expect(described_class.editable?(past)).to be(false)
    end
  end

  it "changes nothing once the booking can no longer be edited" do
    booking = create(:booking, hotel: hotel, status: "cancelled", check_in: hotel.business_date_for + 3, check_out: hotel.business_date_for + 5)

    result = described_class.call(booking: booking, user: user, guests: {})

    expect(result).not_to be_success
    expect(result.errors).to include("This booking can no longer be changed from the portal.")
  end
end
