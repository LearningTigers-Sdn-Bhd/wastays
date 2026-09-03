# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConcierge::Orchestration::HotelKnowledge::HotelOverviewComposer do
  let(:reply_class) { AiConcierge::Orchestration::HotelKnowledge::Reply }

  it "positions the hotel and groups amenities without showing the street address" do
    selected = Hotel::CATEGORIZED_HOTEL_AMENITIES.first(2).flat_map { |group| group.fetch(:items).first(2) }
    hotel = create(
      :hotel,
      name: "Aurora Crown Resort Langkawi",
      star_rating: 5,
      address: "12 Jalan Pantai Tengah",
      city: "Langkawi",
      country: "Malaysia",
      amenities: selected.map { |amenity| amenity.fetch(:id) }
    )
    reply = reply_class.new(
      shape: "list",
      answer_mode: "structured",
      facts: [
        reply_class::Fact.new(topic: "location", text: "The hotel is located at 12 Jalan Pantai Tengah, Langkawi, Malaysia."),
        reply_class::Fact.new(topic: "amenities", text: "Available amenities include #{selected.map { |amenity| amenity.fetch(:name) }.to_sentence}.")
      ],
      success: true
    )

    message = described_class.new(hotel: hotel, reply: reply).call

    expect(message).to start_with("Aurora Crown Resort Langkawi is a 5-star hotel in Langkawi, Malaysia.")
    expect(message).to include("Highlights include:")
    expect(message.lines.count { |line| line.start_with?("- ") }).to be_between(1, 3)
    expect(message).not_to include("12 Jalan Pantai Tengah", "Available amenities include")
  end

  it "uses a distinct approved knowledge detail without repeating a generic summary" do
    hotel = create(:hotel, name: "Aurora Hotel", star_rating: 5, city: "Langkawi", country: "Malaysia", address: "Pantai Tengah")
    reply = reply_class.new(
      shape: "list",
      answer_mode: "deterministic",
      facts: [
        reply_class::Fact.new(topic: "Overview", text: "Aurora Hotel is a 5-star hotel located at Pantai Tengah.", source_refs: [ 1 ]),
        reply_class::Fact.new(topic: "Experience", text: "The property has a quiet garden setting.", source_refs: [ 2 ])
      ],
      success: true
    )

    message = described_class.new(hotel: hotel, reply: reply).call

    expect(message).to include("The property has a quiet garden setting.")
    expect(message.scan(/5-star/).size).to eq(1)
    expect(message).not_to include("Pantai Tengah")
  end

  it "uses tone-specific highlight introductions" do
    amenity = Hotel::HOTEL_AMENITIES.first
    hotel = create(:hotel, amenities: [ amenity.fetch(:id) ])
    reply = reply_class.new(shape: "list", answer_mode: "structured", facts: [], success: true)

    expect(described_class.new(hotel: hotel, reply: reply, tone: "business").call).to include("Key highlights:")
    expect(described_class.new(hotel: hotel, reply: reply, tone: "cheerful").call).to include("A few highlights:")
  end
end
