# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::ProcessCheckIn, frozen_time: :business_day do
  let(:hotel) { create(:hotel, status: "live") }
  let(:user) { create(:user, account: hotel.account) }
  let(:room_type) { create(:room_type, hotel: hotel, room_number_mode: "custom", quantity: 2, room_numbers: %w[101 102]) }
  let(:booking) do
    create(
      :booking,
      hotel: hotel,
      status: "confirmed",
      guest_name: "Ada Lovelace",
      check_in: Time.zone.now,
      check_out: 2.days.from_now
    ).tap do |record|
      create(:booking_room, booking: record, room_type: room_type, room_number: nil)
    end
  end

  before { BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.current) }

  def details(record = booking, room_number: "101")
    {
      checked_in_at: Time.current.in_time_zone(hotel.hotel_time_zone).strftime("%Y-%m-%dT%H:%M"),
      tourism_tax_collected: "0",
      room_assignments: { record.booking_rooms.first.id.to_s => room_number }
    }
  end

  it "checks in a confirmed booking and assigns the requested room" do
    result = described_class.new(bookings: [ booking ], details: details, user: user).call

    expect(result.success?).to be(true)
    expect(booking.reload.status).to eq("checked_in")
    expect(booking.booking_rooms.first.reload.room_number).to eq("101")
  end

  it "fails when no bookings are supplied" do
    result = described_class.new(bookings: [], details: {}, user: user).call

    expect(result.success?).to be(false)
    expect(result.error).to eq("Select at least one booking.")
  end

  it "fails when the booking is not eligible for check-in" do
    ineligible = create(:booking, hotel: hotel, status: "cancelled", check_in: Time.zone.now, check_out: 2.days.from_now)
    create(:booking_room, booking: ineligible, room_type: room_type, room_number: nil)

    result = described_class.new(bookings: [ ineligible ], details: details(ineligible), user: user).call

    expect(result.success?).to be(false)
    expect(result.error).to eq("Selected bookings are no longer eligible for check-in.")
  end

  it "fails when a room is left unassigned" do
    result = described_class.new(bookings: [ booking ], details: details(room_number: ""), user: user).call

    expect(result.success?).to be(false)
    expect(result.error).to match(/Assign every room/)
    expect(booking.reload.status).to eq("confirmed")
  end
end
