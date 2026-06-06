# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::TransitionStatus do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }
  let(:room_type) { create(:room_type, hotel: hotel, room_numbers: [ "101" ]) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in", checked_in_at: 1.day.ago) }

  before do
    create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "ready")
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101", quantity: 1, subtotal: 200)
    Folios::InitializeForBooking.call(booking: booking, user: user)
  end

  it "marks assigned rooms pending_cleaning when the guest checks out" do
    result = described_class.new(booking: booking, status: "completed", timestamp: Time.current, user: user).call

    expect(result).to be_success
    expect(RoomStatus.find_by!(hotel: hotel, room_number: "101").status).to eq("pending_cleaning")

    log = RoomOperationalAuditLog.find_by!(event_type: "checkout_marked_pending_cleaning")
    expect(log.booking).to eq(booking)
    expect(log.user).to eq(user)
    expect(log.old_status).to eq("ready")
    expect(log.new_status).to eq("pending_cleaning")
  end
end
