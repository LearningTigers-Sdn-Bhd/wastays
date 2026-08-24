# frozen_string_literal: true

require "rails_helper"

RSpec.describe Attraction do
  it "uses the shared summary before the name" do
    attraction = build(:attraction, name: "Signal Hill", shared_summary: "A city viewpoint.")

    expect(attraction.display_description).to eq("A city viewpoint.")
  end

  it "exposes a pending attraction to each hotel that adds it" do
    linked_hotel = create(:hotel)
    unlinked_hotel = create(:hotel)
    attraction = create(:attraction, :pending, source_hotel: linked_hotel)
    create(:hotel_nearby_attraction, hotel: linked_hotel, attraction: attraction)

    expect(attraction.visible_to_guests_for?(linked_hotel)).to be(true)
    expect(attraction.visible_to_guests_for?(unlinked_hotel)).to be(false)
  end

  it "requires a review note when an administrator rejects it" do
    attraction = build(:attraction, status: "rejected", review_note: nil)

    expect(attraction).not_to be_valid
    expect(attraction.errors[:review_note]).to include("can't be blank")
  end
end
