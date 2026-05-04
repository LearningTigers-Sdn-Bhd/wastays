require "rails_helper"

RSpec.describe AiConciergeV3::Tools::SearchBookingOptionsTool do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Deluxe Room", max_adults: 2) }

  before do
    [ 11, 12, 13, 14 ].each_with_index do |day, index|
      date = Date.new(2026, 8, day)
      create(:room_rate, room_type: room_type, date: date, price: 200 + index, currency: "MYR")
      create(:room_inventory, room_type: room_type, date: date, quantity: 2, status: "open")
    end
  end

  it "returns grouped options with room type names and selection ids" do
    result = described_class.new(
      hotel: hotel,
      target_month: 8,
      target_year: 2026,
      month_segment: "mid",
      adults: 2,
      children: 0,
      room_count: 1,
      nights: 2
    ).call

    expect(result).not_to be_empty
    expect(result.first["room_type_id"]).to eq(room_type.id)
    expect(result.first["room_type_name"]).to eq("Deluxe Room")
    expect(result.first.dig("options", 0, "position")).to eq(1)
    expect(result.first.dig("options", 0, "selection_id")).to be_present
  end
end
