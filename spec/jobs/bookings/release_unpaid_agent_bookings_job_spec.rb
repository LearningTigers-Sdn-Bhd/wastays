# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::ReleaseUnpaidAgentBookingsJob do
  it "runs the sweep" do
    expect(Bookings::ReleaseUnpaidAgentBookings).to receive(:call).and_return(
      Bookings::ReleaseUnpaidAgentBookings::Result.new(released: [], skipped: [], failed: [])
    )

    described_class.perform_now
  end

  it "releases an agent booking whose deadline has passed" do
    hotel = create(:hotel, status: "live")
    relationship = create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent")
    booking = create(:booking, hotel: hotel, hotel_corporate_account: relationship,
                               status: "confirmed", payment_status: "pending",
                               payment_due_at: 1.hour.ago)

    described_class.perform_now

    expect(booking.reload.status).to eq("cancelled")
  end
end
