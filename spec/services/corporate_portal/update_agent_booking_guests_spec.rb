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
  it "updates and audits types even when the time stays the same" do
    hotel.update!(allow_boat_information: true)
    booking = create(:booking, hotel: hotel, status: "confirmed", check_in: hotel.business_date_for + 3, check_out: hotel.business_date_for + 5)
    lead = create(:booking_guest, booking: booking, is_primary: true, boat_in_type: "provided",
      boat_in_at: Boats::Schedule.timestamp(hotel: hotel, date: booking.check_in, time: "09:00"))
    result = described_class.call(booking: booking, user: user, guests: {},
      boat: { boat_in_time: "charter", boat_in_custom_time: "09:00", boat_out_time: "own" })
    expect(result).to be_success
    expect(lead.reload).to have_attributes(boat_in_type: "charter", boat_out_type: "own", boat_out_at: nil)
    audit = BookingAuditLog.where(auditable: booking, action_type: "guest_updated").order(:id).last
    expect(audit.old_value).to include("boat_in_type" => "provided", "boat_out_type" => nil)
    expect(audit.new_value).to include("boat_in_type" => "charter", "boat_out_type" => "own")
  end
end
