# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Core::RateQuestion do
  def asks_about_price?(message) = described_class.new(message: message).call

  # Rates depend on dates, so the honest answer to any of these is a quote.
  it "recognises a guest asking what a stay costs" do
    expect(asks_about_price?("how much is a room here?")).to be(true)
    expect(asks_about_price?("what are your room rates?")).to be(true)
    expect(asks_about_price?("what is the price for a room in august?")).to be(true)
    expect(asks_about_price?("how much per night?")).to be(true)
    expect(asks_about_price?("cost of the ocean villa?")).to be(true)
    expect(asks_about_price?("find the cheapest room")).to be(true)
  end

  # "Room service" contains the word room and is never a room.
  it "does not mistake room service for a room" do
    expect(asks_about_price?("how much is room service?")).to be(false)
    expect(asks_about_price?("do you have room service?")).to be(false)
  end

  it "leaves questions that are not about money alone" do
    expect(asks_about_price?("is there parking?")).to be(false)
    expect(asks_about_price?("what time is check in?")).to be(false)
    expect(asks_about_price?("tell me about the ocean villa")).to be(false)
  end
end
