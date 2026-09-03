require "rails_helper"

RSpec.describe AiConcierge::MessageBuilders::GreetingBuilder do
  it "welcomes the guest and explains the available paths" do
    hotel = build_stubbed(:hotel, name: "Aurora Crown Resort Langkawi")

    message = described_class.new(hotel: hotel, context: {}).call(:greeting)

    expect(message).to eq(
      "Hello! Welcome to Aurora Crown Resort Langkawi. I can help you find the right stay, check prices, " \
        "answer hotel questions, or access an existing booking. What can I help you with today?"
    )
  end

  it "does not render another reply type" do
    hotel = build_stubbed(:hotel)

    expect(described_class.new(hotel: hotel, context: {}).call(:ask_duration)).to be_nil
  end
end
