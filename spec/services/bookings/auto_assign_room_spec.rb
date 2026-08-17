require "rails_helper"

RSpec.describe Bookings::AutoAssignRoom do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, quantity: 2, room_numbers: %w[101 102]) }
  let(:check_in) { Date.current + 2.days }
  let(:check_out) { check_in + 2.days }
  let(:booking) do
    create(:booking, hotel: hotel, status: "confirmed", check_in: check_in, check_out: check_out).tap do |record|
      create(:booking_room, booking: record, room_type: room_type)
    end
  end

  before do
    (check_in...check_out).each do |date|
      create(:room_inventory, room_type: room_type, date: date, quantity: 2, status: "open")
    end
  end

  it "leaves the booking alone when the property has the setting off" do
    hotel.update!(auto_assign_rooms_enabled: false)

    result = described_class.new(booking: booking).call

    expect(result).to be_success
    expect(result).not_to be_assigned
    expect(booking.booking_rooms.sole.reload.room_number).to be_nil
  end

  it "assigns the first physical room available for the full stay" do
    result = described_class.new(booking: booking).call

    expect(result).to be_success
    expect(result).to be_assigned
    expect(booking.booking_rooms.sole.reload.room_number).to eq("101")
    expect(BookingAuditLog.where(auditable: booking.booking_rooms.sole).last.metadata)
      .to include("automatic" => true, "source" => "channel_manager")
  end

  it "skips an overlapping room and assigns the next available room" do
    occupied = create(:booking, hotel: hotel, status: "confirmed", check_in: check_in, check_out: check_out)
    create(:booking_room, booking: occupied, room_type: room_type, room_number: "101")

    described_class.new(booking: booking).call

    expect(booking.booking_rooms.sole.reload.room_number).to eq("102")
  end

  it "keeps the booking unassigned when no physical room is assignable" do
    %w[101 102].each do |room_number|
      create(:room_status, hotel: hotel, room_type: room_type, room_number: room_number, status: "dirty")
    end

    result = described_class.new(booking: booking).call

    expect(result).to be_success
    expect(result).not_to be_assigned
    expect(booking.booking_rooms.sole.reload.room_number).to be_nil
  end

  it "replaces an assignment that conflicts with another booking" do
    booking.booking_rooms.sole.update!(room_number: "101")
    occupied = create(:booking, hotel: hotel, status: "confirmed", check_in: check_in, check_out: check_out)
    create(:booking_room, booking: occupied, room_type: room_type, room_number: "101")

    described_class.new(booking: booking).call

    expect(booking.booking_rooms.sole.reload.room_number).to eq("102")
    removal = BookingAuditLog.where(auditable: booking.booking_rooms.sole, action_type: "room_removed").last
    expect(removal).to be_present
    expect(removal.metadata).to include("automatic" => true)
  end
end
