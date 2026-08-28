require "rails_helper"

RSpec.describe AiConcierge::Matching::BookingIntentMatcher do
  it "reads asking how to book as a question about booking" do
    expect(described_class.new(message: "how to make booking?")).to be_how_to_question
    expect(described_class.new(message: "can i make a booking?")).to be_how_to_question
    expect(described_class.new(message: "where do i reserve a room")).to be_how_to_question
  end

  it "does not read a plain booking request as a how-to question" do
    expect(described_class.new(message: "i want to book a room")).not_to be_how_to_question
    expect(described_class.new(message: "book 2 nights please")).not_to be_how_to_question
  end

  it "does not read a policy question as a booking of any kind" do
    matcher = described_class.new(message: "can i cancel my booking")

    expect(matcher).not_to be_booking
    expect(matcher).not_to be_how_to_question
  end

  it "separates price exploration from explicit booking commitment" do
    expect(described_class.new(message: "find the cheapest room")).to be_rate_question
    expect(described_class.new(message: "find the cheapest room")).not_to be_booking_commitment
    expect(described_class.new(message: "book the cheapest room")).to be_booking_commitment
    expect(described_class.new(message: "continue with option 1")).to be_booking_commitment
  end

  it "requires book or reserve language for a price-shopping purchase" do
    %w[yes continue proceed].each do |message|
      expect(described_class.new(message: message)).not_to be_explicit_purchase_commitment
    end
    expect(described_class.new(message: "book this option")).to be_explicit_purchase_commitment
    expect(described_class.new(message: "reserve option 2")).to be_explicit_purchase_commitment
    expect(described_class.new(message: "make a booking")).to be_explicit_purchase_commitment
    expect(described_class.new(message: "I have a booking question")).not_to be_explicit_purchase_commitment
  end
end
