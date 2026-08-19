require "rails_helper"

RSpec.describe Reports::Bookings::GenerateVoucherPack do
  let(:hotel) { create(:hotel, name: "Seaview Hotel") }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Deluxe") }
  let(:group_booking) { create(:group_booking, hotel: hotel, name: "Tanaka Wedding") }

  def create_child(position:, token:, status: "confirmed")
    child = create(:booking,
      hotel: hotel,
      group_booking: group_booking,
      group_position: position,
      status: status,
      confirmation_token: token,
      total_amount: 300.0,
      check_in: Date.new(2026, 5, 1),
      check_out: Date.new(2026, 5, 3),
      hotel_snapshot: { "property_policy" => { "check_in_time" => "3:00 PM", "cancellation_policy" => "No refund" } })
    create(:booking_room, booking: child, room_type: room_type, subtotal: 300.0,
      room_type_snapshot: { "name" => "Deluxe" })
    child
  end

  def pages(pdf) = PDF::Reader.new(StringIO.new(pdf)).pages

  it "prints one voucher page per room, in group order" do
    create_child(position: 1, token: "WS-ROOM1")
    create_child(position: 2, token: "WS-ROOM2")
    create_child(position: 3, token: "WS-ROOM3")

    result = pages(described_class.new(group_booking).generate)

    expect(result.size).to eq(3)
    expect(result.map(&:text).map { |text| text[/WS-ROOM\d/] }).to eq(%w[WS-ROOM1 WS-ROOM2 WS-ROOM3])
  end

  # Each guest is handed their own page, and a leader may never pass the terms on, so a
  # page has to carry everything it needs once it is torn off the stack.
  it "gives every page a full masthead, its own confirmation code, and the policies" do
    create_child(position: 1, token: "WS-ROOM1")
    create_child(position: 2, token: "WS-ROOM2")

    result = pages(described_class.new(group_booking).generate)

    result.each do |page|
      expect(page.text).to include("Seaview Hotel", "BOOKING VOUCHER", "Property policies")
      expect(page.text).to include("Please present this voucher at check-in.")
    end
    expect(result.first.text).to include("Confirmation WS-ROOM1")
    expect(result.first.text).not_to include("WS-ROOM2")
  end

  it "numbers the furniture across the whole pack" do
    create_child(position: 1, token: "WS-ROOM1")
    create_child(position: 2, token: "WS-ROOM2")

    result = pages(described_class.new(group_booking).generate)

    result.each_with_index do |page, index|
      expect(page.text).to include("Page #{index + 1} of #{result.size}")
    end
  end

  # Dropping it would leave the organiser counting pages against rooms and coming up short.
  it "prints a cancelled room too, badged as cancelled" do
    create_child(position: 1, token: "WS-ROOM1")
    create_child(position: 2, token: "WS-ROOM2", status: "cancelled")

    result = pages(described_class.new(group_booking).generate)

    expect(result.size).to eq(2)
    expect(result.last.text).to include("WS-ROOM2", "CANCELLED")
  end

  it "states no money on any page" do
    create_child(position: 1, token: "WS-ROOM1")

    text = pages(described_class.new(group_booking).generate).map(&:text).join("\n")

    expect(text).not_to include("Total due", "Payments", "Balance due", "300.00")
  end

  it "refuses a group with nothing to print rather than emitting an empty file" do
    expect { described_class.new(group_booking).generate }
      .to raise_error(described_class::EmptyGroupError)
  end
end
