require "rails_helper"

RSpec.describe AiConciergeV3::Tools::Booking::SearchBookingOptionsTool do
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

  context "alignment across room types" do
    let!(:room_type_a) { create(:room_type, hotel: hotel, name: "Room A", max_adults: 2) }
    let!(:room_type_b) { create(:room_type, hotel: hotel, name: "Room B", max_adults: 2) }

    before do
      # Room A available May 21..28
      # Room B available May 24..31
      # nights = 3

      (21..31).each do |day|
        date = Date.new(2026, 5, day)
        # Room A
        if day <= 28
          create(:room_rate, room_type: room_type_a, date: date, price: 100)
          create(:room_inventory, room_type: room_type_a, date: date, quantity: 1, status: "open")
        end
        # Room B
        if day >= 24
          create(:room_rate, room_type: room_type_b, date: date, price: 200)
          create(:room_inventory, room_type: room_type_b, date: date, quantity: 1, status: "open")
        end
      end
    end

    it "aligns the date options for both rooms to May 24, 25, 26 (highest common availability)" do
      result = described_class.new(
        hotel: hotel,
        target_month: 5,
        target_year: 2026,
        month_segment: "late",
        adults: 2,
        children: 0,
        room_count: 1,
        nights: 3
      ).call

      group_a = result.find { |g| g["room_type_name"] == "Room A" }
      group_b = result.find { |g| g["room_type_name"] == "Room B" }

      dates_a = group_a["options"].map { |o| o["check_in"] }
      dates_b = group_b["options"].map { |o| o["check_in"] }

      # They should both prioritize May 24, 25, 26 because those dates have 2 rooms available
      # whereas 21, 22, 23 only have 1 room available.
      expect(dates_a).to eq([ "2026-05-24", "2026-05-25", "2026-05-26" ])
      expect(dates_b).to eq([ "2026-05-24", "2026-05-25", "2026-05-26" ])
    end

    it "falls back to individual availability if a room is not available on aligned dates" do
      room_type_c = create(:room_type, hotel: hotel, name: "Room C", max_adults: 2)
      # Room C only available May 21, 22
      (21..22).each do |day|
        date = Date.new(2026, 5, day)
        create(:room_rate, room_type: room_type_c, date: date, price: 300)
        create(:room_inventory, room_type: room_type_c, date: date, quantity: 1, status: "open")
      end

      result = described_class.new(
        hotel: hotel,
        target_month: 5,
        target_year: 2026,
        month_segment: "late",
        adults: 2,
        children: 0,
        room_count: 1,
        nights: 1 # shorter stay to make 21, 22 available
      ).call

      group_c = result.find { |g| g["room_type_name"] == "Room C" }
      dates_c = group_c["options"].map { |o| o["check_in"] }

      # Best dates will still be 24, 25, 26 because A and B are available then.
      # Room C is not available on 24, 25, 26, so it should fall back to its own dates.
      expect(dates_c).to include("2026-05-21")
      expect(dates_c).to include("2026-05-22")
    end
  end
end
