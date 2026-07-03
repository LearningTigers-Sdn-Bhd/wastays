# frozen_string_literal: true

require "rails_helper"

RSpec.describe GroupBookings::CreateFromBookings do
  it "groups independent one-room bookings without changing child stay data" do
    hotel = create(:hotel)
    first = create(:booking, hotel: hotel)
    second = create(:booking, hotel: hotel)
    create(:booking_room, booking: first, quantity: 1)
    create(:booking_room, booking: second, quantity: 1)

    result = described_class.call(
      hotel: hotel,
      bookings: [ first, second ],
      attributes: { reference: "GRP-100", name: "Wedding" }
    )

    expect(result).to be_success
    expect(result.group_booking.bookings.reload).to contain_exactly(first, second)
    expect(first.reload.group_position).to eq(1)
    expect(second.reload.group_position).to eq(2)
  end

  it "rejects an aggregated room booking" do
    hotel = create(:hotel)
    aggregated = create(:booking, hotel: hotel)
    normal = create(:booking, hotel: hotel)
    create(:booking_room, booking: aggregated, quantity: 2)
    create(:booking_room, booking: normal, quantity: 1)

    result = described_class.call(
      hotel: hotel,
      bookings: [ aggregated, normal ],
      attributes: { reference: "GRP-101", name: "Invalid" }
    )

    expect(result).not_to be_success
    expect(result.error).to include("exactly one room")
  end

  it "projects status from children and removes membership without changing the booking lifecycle" do
    group = create(:group_booking)
    first = create(:booking, hotel: group.hotel, group_booking: group, group_position: 1, status: "completed")
    second = create(:booking, hotel: group.hotel, group_booking: group, group_position: 2, status: "cancelled")

    expect(group.projected_status).to eq("completed")

    result = GroupBookings::RemoveBooking.call(group_booking: group, booking: second, actor: nil, reason: "Moved independently")

    expect(result).to be_success
    expect(second.reload).to have_attributes(group_booking_id: nil, group_position: nil, status: "cancelled")
  end
end
