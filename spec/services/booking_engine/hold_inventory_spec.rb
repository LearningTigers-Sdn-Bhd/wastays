require "rails_helper"

RSpec.describe BookingEngine::HoldInventory do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:quote) { create(:booking_quote, hotel: hotel, check_in: Date.current, check_out: Date.current + 2) }

  before do
    create(:booking_quote_item, booking_quote: quote, room_type: room_type, quantity: 1)
    (quote.check_in...quote.check_out).each do |date|
      create(:room_inventory, room_type: room_type, date: date, quantity: 5, status: "open")
    end
  end

  it "decrements inventory for each stay date" do
    result = described_class.new(quote).call

    expect(result).to be(true)
    quantities = room_type.room_inventories.where(date: quote.check_in...quote.check_out).pluck(:quantity)
    expect(quantities).to all(eq(4))
  end

  it "returns false when inventory is insufficient" do
    room_type.room_inventories.first.update!(quantity: 0)

    result = described_class.new(quote).call
    expect(result).to be_nil
  end
end
