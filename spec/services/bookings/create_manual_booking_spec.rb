# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::CreateManualBooking do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, quantity: 5) }
  let(:params) do
    {
      guest_name: "Test Guest",
      guest_email: "test@example.com",
      guest_phone: "123456",
      check_in: Date.current,
      check_out: Date.current + 1.day,
      room_type_id: room_type.id,
      room_number: "101",
      adults: 2
    }
  end

  subject { described_class.new(hotel: hotel, params: params) }

  it "creates a booking and deducts inventory" do
    result = subject.call
    expect(result.success?).to be true
    expect(result.booking).to be_persisted
    expect(result.booking.hotel_snapshot["room_number"]).to eq("101")

    inventory = room_type.room_inventories.find_by(date: Date.current)
    expect(inventory.quantity).to eq(4)
  end

  it "returns errors when booking fails" do
    params[:guest_name] = nil
    result = subject.call
    expect(result.success?).to be false
    expect(result.errors).to include("Guest name can't be blank")
  end
end
