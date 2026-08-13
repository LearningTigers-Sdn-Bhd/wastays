# frozen_string_literal: true

require "rails_helper"

RSpec.describe RatePlans::Autocomplete do
  let(:hotel) { create(:hotel) }

  it "returns matching active custom plans with room usage descriptions" do
    breakfast = create(:rate_plan, :custom, hotel: hotel, name: "Breakfast Included")
    rooms = create_list(:room_type, 2, hotel: hotel)
    rooms.each { |room| create(:room_type_rate_plan, rate_plan: breakfast, room_type: room) }
    create(:rate_plan, :custom, hotel: hotel, name: "Non-refundable")

    results = described_class.call(hotel: hotel, query: "break")

    expect(results).to eq([
      { id: breakfast.id, label: "Breakfast Included", description: "Used by 2 room categories" }
    ])
  end

  it "excludes protected, archived, and cross-hotel plans" do
    create(:room_type, hotel: hotel).standard_rate_plan
    create(:rate_plan, :custom, hotel: hotel, name: "Archived Promo", archived_at: Time.current)
    create(:rate_plan, :custom, name: "Other Hotel Promo")

    expect(described_class.call(hotel: hotel)).to be_empty
  end
end
