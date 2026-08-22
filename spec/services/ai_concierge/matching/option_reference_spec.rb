# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConcierge::Matching::OptionReference do
  def read(message) = described_class.new(message: message)

  it "reads the row out of the shapes guests write it in" do
    {
      "2" => 2, "no 2" => 2, "2nd" => 2, "option 2" => 2, "number 2" => 2,
      "the second one" => 2, "option two" => 2, "i'll take 2" => 2, "2 please" => 2
    }.each do |message, number|
      expect(read(message).number).to eq(number), "expected #{message.inspect} to read as row #{number}"
    end
  end

  # A number that counts something else is not a row, and neither is the
  # ordinal in a date.
  it "reads nothing out of a number that counts something else" do
    [ "2 nights", "2 rooms", "2 adults", "august 3rd", "garden prestige" ].each do |message|
      expect(read(message).number).to be_nil, "expected #{message.inspect} not to read as a row"
    end
  end

  # The question this answers is what the message is safe to be read for: a
  # message that is only a row says nothing about rates, nights or people.
  it "knows when the row is all the guest said" do
    [ "2", "no 2", "the second one" ].each do |message|
      expect(read(message)).to be_only_reference
    end

    [ "garden prestige option 2", "2 nights", "option 2 standard rate" ].each do |message|
      expect(read(message)).not_to be_only_reference
    end
  end
end
