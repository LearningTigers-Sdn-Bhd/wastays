# frozen_string_literal: true

require "rails_helper"

RSpec.describe LegacyBookingSplitLineage do
  it "is immutable after creation" do
    booking = create(:booking)
    room = create(:booking_room, booking:, room_type: create(:room_type, hotel: booking.hotel))
    group = create(:group_booking, hotel: booking.hotel)
    booking.update!(group_booking: group, group_position: 1)
    lineage = create(:legacy_booking_split_lineage, legacy_booking: booking, child_booking: booking,
      booking_room: room, group_booking: group)

    expect(lineage.update(review_reason: "changed")).to be(false)
    expect(lineage.destroy).to be(false)
  end

  it "allows a pending review to be approved once without changing lineage identity" do
    booking = create(:booking)
    room = create(:booking_room, booking:, room_type: create(:room_type, hotel: booking.hotel))
    group = create(:group_booking, hotel: booking.hotel)
    booking.update!(group_booking: group, group_position: 1)
    lineage = create(
      :legacy_booking_split_lineage,
      legacy_booking: booking,
      child_booking: booking,
      booking_room: room,
      group_booking: group,
      review_status: "pending"
    )

    expect(lineage.update(review_status: "approved", review_reason: "Reviewed by finance")).to be(true)
    expect(lineage.update(review_status: "rejected", review_reason: "Changed again")).to be(false)
  end
end
