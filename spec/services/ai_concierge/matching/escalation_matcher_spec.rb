# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConcierge::Matching::EscalationMatcher do
  it "recognizes unambiguous requests for a person" do
    expect(described_class.new(message: "I need to speak to a manager").call).to eq("guest_asks_for_person")
    expect(described_class.new(message: "Human please").call).to eq("guest_asks_for_person")
  end

  it "recognizes unambiguous emergencies" do
    expect(described_class.new(message: "There is a fire in the corridor").call).to eq("emergency")
    expect(described_class.new(message: "My partner is unconscious").call).to eq("emergency")
  end

  it "does not classify ordinary requests as escalation" do
    expect(described_class.new(message: "What is your payment policy?").call).to be_nil
    expect(described_class.new(message: "What time does the front desk open?").call).to be_nil
  end
end
