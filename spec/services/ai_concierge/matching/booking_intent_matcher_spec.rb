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
end
