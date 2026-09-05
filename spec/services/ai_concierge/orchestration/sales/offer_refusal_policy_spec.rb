require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Sales::OfferRefusalPolicy do
  let(:sales_task) { { "last_optional_action" => "offer_booking_help" } }

  it "ignores negative words when no optional offer awaits an answer" do
    result = described_class.new(message: "no thanks", sales_task: {}).call

    expect(result).not_to be_refusal
  end

  it "recognizes standalone English, Malay, and Chinese refusals" do
    [ "no thanks", "tak mahu", "不用" ].each do |message|
      result = described_class.new(message: message, sales_task: sales_task).call

      expect(result).to be_refusal
      expect(result).to be_standalone
    end
  end

  it "recognizes a refusal before a new question" do
    result = described_class.new(message: "no thanks, what time is check-out?", sales_task: sales_task).call

    expect(result).to be_refusal
    expect(result).not_to be_standalone
  end

  it "does not treat an unrelated sentence as a refusal" do
    result = described_class.new(message: "what time is check-out?", sales_task: sales_task).call

    expect(result).not_to be_refusal
  end
end
