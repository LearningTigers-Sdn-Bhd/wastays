# frozen_string_literal: true

require "rails_helper"

RSpec.describe StayView::ResolveCurrentRoomStatus do
  it "separates late checkout detection from physical readiness" do
    status = StayView::RoomStatusRecord.new(
      room_type_id: 3,
      room_number: "101",
      status: :late_checkout_detected,
      priority: true,
      dnd: true,
      dnd_date: Date.new(2026, 7, 16)
    )

    result = described_class.call(room_status: status, operational_date: Date.new(2026, 7, 16))

    expect(result.physical_status).to be_nil
    expect(result.operational_flags).to eq(priority: true, dnd: true, late_checkout: true)
    expect(result.operational_flags).to be_frozen
  end
end
