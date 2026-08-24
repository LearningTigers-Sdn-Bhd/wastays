# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelNearbyAttraction do
  it "uses the hotel description before the shared summary" do
    link = build(:hotel_nearby_attraction,
      description: "Our local recommendation.",
      attraction: build(:attraction, shared_summary: "Shared summary."))

    expect(link.guest_description).to eq("Our local recommendation.")
  end
end
