# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::InventoryManager do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, quantity: 10) }
  let(:booking) { create(:booking, hotel: hotel, check_in: Date.current, check_out: Date.current + 1.day) }
  let!(:booking_room) { create(:booking_room, booking: booking, room_type: room_type, quantity: 1) }

  subject { described_class.new(booking) }

  it "deducts inventory" do
    subject.deduct
    inventory = room_type.room_inventories.find_by(date: Date.current)
    expect(inventory.quantity).to eq(9)
  end

  it "releases inventory" do
    subject.deduct
    subject.release
    inventory = room_type.room_inventories.find_by(date: Date.current)
    expect(inventory.quantity).to eq(10)
  end

  it "releases inventory by specific dates" do
    subject.deduct
    subject.release_by_dates(Date.current, Date.current + 1.day)
    inventory = room_type.room_inventories.find_by(date: Date.current)
    expect(inventory.quantity).to eq(10)
  end
end
