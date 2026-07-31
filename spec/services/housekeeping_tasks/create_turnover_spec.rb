# frozen_string_literal: true

require "rails_helper"

RSpec.describe HousekeepingTasks::CreateTurnover do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, room_number_mode: "custom", room_numbers: %w[101 102]) }
  let(:booking) { create(:booking, hotel: hotel, status: "completed") }

  def turnovers_for(booking) = HousekeepingRequest.checkout_turnovers.where(booking_id: booking.id)

  it "raises a turnover for the room the guest left" do
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")

    described_class.new(booking: booking).call

    expect(turnovers_for(booking).sole).to have_attributes(
      room_number: "101",
      room_type: room_type,
      hotel: hotel,
      status: "new"
    )
  end

  # A stay holds one room, and a party of rooms is a group of stays -- so each
  # child's own departure raises its own turnover. Pinned here so that reading
  # the booking's rooms stays the thing this asks, rather than the booking.
  it "raises one per room the stay holds" do
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")

    described_class.new(booking: booking).call

    expect(turnovers_for(booking).pluck(:room_number)).to eq(booking.booking_rooms.pluck(:room_number))
  end

  # Never the guest's own words: somebody who wrote "late checkout until 2pm"
  # into the concierge page has told the front desk something, and a housekeeper
  # handed that as their instruction has been told nothing about the room.
  it "always calls the work what it is" do
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
    create(:check_out_request, booking: booking, guest_notes: "Requesting late checkout until 2pm")

    described_class.new(booking: booking).call

    expect(turnovers_for(booking).sole.request_details).to eq("Checkout turnover")
  end

  it "does not ask for the same room twice" do
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")

    2.times { described_class.new(booking: booking).call }

    expect(turnovers_for(booking).count).to eq(1)
  end

  # A room cleaned after an earlier departure is owed a fresh turnover, not
  # nothing -- the closed task is history, not the work still standing.
  it "asks again once the earlier turnover is finished" do
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
    described_class.new(booking: booking).call
    turnovers_for(booking).sole.update!(status: "completed", completed_at: Time.current)

    described_class.new(booking: booking).call

    expect(turnovers_for(booking).count).to eq(2)
  end

  it "skips a room with no number to clean" do
    create(:booking_room, booking: booking, room_type: room_type, room_number: nil)

    expect(described_class.new(booking: booking).call).to be_empty
  end
end
