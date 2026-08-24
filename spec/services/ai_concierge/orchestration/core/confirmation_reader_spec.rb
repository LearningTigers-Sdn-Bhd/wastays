# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Core::ConfirmationReader do
  def read(message) = described_class.new(message: message).as_interpretation

  it "reads the ways a guest says yes" do
    [ "yes", "Yes!", "yep", "sure", "ok", "confirm" ].each do |message|
      expect(read(message)).to eq("intent" => "confirmation", "slots" => { "confirmation" => "yes" })
    end
  end

  it "reads the ways a guest says no" do
    [ "no", "Nope.", "not really" ].each do |message|
      expect(read(message)).to eq("intent" => "confirmation", "slots" => { "confirmation" => "no" })
    end
  end

  # A sentence that merely contains "yes" is not an answer to a yes/no
  # question, and reading it as one would end conversations people meant to
  # continue.
  it "does not read a yes out of the middle of a sentence" do
    expect(read("yes please tell me about the pool")["intent"]).to be_nil
    expect(read("i want to book")["intent"]).to be_nil
  end

  it "reads a yes softened by politeness" do
    [ "yes please", "ok thanks", "sure la" ].each do |message|
      expect(read(message).dig("slots", "confirmation")).to eq("yes")
    end
  end

  # The replies the guest reads are written in their own language, so the
  # answers come back in it too.
  it "reads a yes and a no in the guest's own language" do
    [ "ya", "betul", "好的", "可以" ].each do |message|
      expect(read(message).dig("slots", "confirmation")).to eq("yes")
    end

    [ "tak", "tidak", "不要" ].each do |message|
      expect(read(message).dig("slots", "confirmation")).to eq("no")
    end
  end
end
