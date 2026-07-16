# frozen_string_literal: true

require "rails_helper"

RSpec.describe StayView::LoadInventory do
  let(:start_date) { Date.new(2026, 7, 16) }
  let(:hotel) { create(:hotel, accounting_business_date: start_date) }
  let(:window) { StayView::DateWindow.new(hotel:, start_date:, days: 7) }
  let(:capabilities) do
    StayView::Capabilities.new(
      **StayView::Capabilities.members.index_with { false }.merge(view_board: true, view_room_readiness: true)
    )
  end

  it "loads bounded scalar inventory and redacts booking identity without permission" do
    room_type = create(:room_type, hotel:, room_numbers: [ "101" ])
    create(:room_status, hotel:, room_type:, room_number: "101", status: "dirty")
    booking = create(
      :booking,
      hotel:,
      check_in: start_date,
      check_out: start_date + 2.days,
      guest_name: "Sensitive Name"
    )
    create(:booking_room, booking:, room_type:, room_number: "101")
    create(
      :room_block,
      hotel:,
      room_type:,
      room_number: "101",
      start_date:,
      end_date: start_date + 1.day
    )

    inventory = described_class.call(hotel:, date_window: window, capabilities:)

    expect(inventory.room_types.map(&:id)).to eq([ room_type.id ])
    expect(inventory.bookings.map(&:guest_name)).to eq([ nil ])
    expect(inventory.room_statuses.map(&:status)).to eq([ :dirty ])
    expect(inventory.room_blocks.size).to eq(1)
    expect(inventory).to be_frozen
    expect(inventory.bookings).to be_frozen
  end
end
