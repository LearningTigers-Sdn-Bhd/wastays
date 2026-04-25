# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::UpdateStayService do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, quantity: 10) }
  let(:booking) { create(:booking, hotel: hotel, check_in: Date.current, check_out: Date.current + 1.day) }
  let!(:booking_room) { create(:booking_room, booking: booking, room_type: room_type, quantity: 1) }

  before do
    Bookings::InventoryManager.new(booking).deduct
  end

  it "updates dates and resyncs inventory" do
    params = { check_in: Date.current + 1.day, check_out: Date.current + 2.days }
    result = described_class.new(booking: booking, params: params).call

    expect(result.success?).to be true
    expect(room_type.room_inventories.find_by(date: Date.current).quantity).to eq(10)
    expect(room_type.room_inventories.find_by(date: Date.current + 1.day).quantity).to eq(9)
  end

  it "updates room type and resyncs inventory" do
    new_room_type = create(:room_type, hotel: hotel, quantity: 5)
    params = { room_type_id: new_room_type.id }

    result = described_class.new(booking: booking, params: params).call

    expect(result.success?).to be true
    expect(room_type.room_inventories.find_by(date: Date.current).quantity).to eq(10)
    expect(new_room_type.room_inventories.find_by(date: Date.current).quantity).to eq(4)
  end
end
