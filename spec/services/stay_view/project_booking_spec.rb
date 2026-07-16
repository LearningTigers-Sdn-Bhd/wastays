# frozen_string_literal: true

require "rails_helper"

RSpec.describe StayView::ProjectBooking do
  let(:window) do
    hotel = create(:hotel, accounting_business_date: Date.new(2026, 7, 16))
    StayView::DateWindow.new(hotel:, start_date: "2026-07-16", days: 7)
  end

  let(:capabilities) do
    StayView::Capabilities.new(
      **StayView::Capabilities.members.index_with { false }.merge(view_board: true, view_booking: false)
    )
  end

  it "projects clipped centre-aligned geometry and redacts guest identity" do
    booking = StayView::BookingRecord.new(
      booking_room_id: 11,
      booking_id: 7,
      room_type_id: 3,
      room_number: "101",
      status: :confirmed,
      guest_name: "Ada Lovelace",
      check_in: Date.new(2026, 7, 14),
      check_out: Date.new(2026, 7, 24)
    )

    segment = described_class.call(booking:, room_type_name: "Deluxe", date_window: window, capabilities:)

    expect(segment.start_track).to eq(1)
    expect(segment.end_track).to eq(15)
    expect(segment).to be_clipped_left
    expect(segment).to be_clipped_right
    expect(segment.guest_label).to eq("Reserved")
    expect(segment.accessible_label).not_to include("Ada Lovelace")
  end
end
