# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::ValidateStayProposal do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel:, room_number_mode: "custom", room_numbers: %w[101 102]) }
  let(:booking) { create(:booking, hotel:, check_in: Date.current, check_out: Date.current + 2.days) }

  before { create(:booking_room, booking:, room_type:, room_number: "101") }

  it "accepts a configured room that is available while excluding the current booking" do
    errors = described_class.call(
      booking:, room_type:, room_number: "101", check_in: booking.check_in, check_out: booking.check_out
    )

    expect(errors).to be_empty
  end

  it "reports invalid date order, unconfigured rooms, and occupied rooms" do
    invalid = described_class.call(
      booking:, room_type:, room_number: "999", check_in: booking.check_out, check_out: booking.check_in
    )
    conflict = create(:booking, hotel:, check_in: Date.current + 2.days, check_out: Date.current + 4.days)
    create(:booking_room, booking: conflict, room_type:, room_number: "102")
    occupied = described_class.call(
      booking:, room_type:, room_number: "102", check_in: Date.current + 2.days, check_out: Date.current + 3.days
    )

    expect(invalid).to contain_exactly("Checkout must be after check-in.", "Select a configured room.")
    expect(occupied).to eq([ "Room 102 is not available for these dates." ])
  end
end
