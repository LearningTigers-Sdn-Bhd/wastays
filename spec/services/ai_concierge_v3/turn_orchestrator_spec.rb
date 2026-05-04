require "rails_helper"

RSpec.describe AiConciergeV3::TurnOrchestrator do
  let(:hotel) { create(:hotel, :with_ai_concierge) }

  before do
    create(:property_policy, hotel: hotel)
  end

  it "asks for duration after a month window is provided" do
    allow_any_instance_of(AiConciergeV3::InterpreterAgent).to receive(:call).and_return(
      interpretation(slots: { "target_month" => 8, "target_year" => 2026, "month_segment" => "mid", "days" => 3, "nights" => 2 })
    )

    result = described_class.new(hotel: hotel, message: "mid august", phone: "+60123456789", identity_mode: :known_contact).call

    expect(result).to be_success
    expect(result.payload[:reply_message]).to include("How many days and nights")
    expect(result.payload[:action_name]).to eq("request_quote")
  end

  it "asks for booking timing when the interpreter invents a month for a vague message" do
    allow_any_instance_of(AiConciergeV3::InterpreterAgent).to receive(:call).and_return(
      interpretation(slots: { "target_month" => 5, "target_year" => 2026, "month_segment" => "early", "adults" => 2, "children" => 0 })
    )

    result = described_class.new(hotel: hotel, message: "hello, is there any booking for 2 adults", phone: "+60123456789", identity_mode: :known_contact).call

    expect(result).to be_success
    expect(result.payload[:reply_message]).to include("What dates or month")
    expect(result.payload[:reply_message]).not_to include("May")
  end

  it "preserves people as a split clarification when the interpreter invents adults" do
    allow_any_instance_of(AiConciergeV3::InterpreterAgent).to receive(:call) do |agent|
      current_message = agent.instance_variable_get(:@message)

      if current_message == "can i book for early june? for 2 people"
        interpretation(slots: { "target_month" => 6, "target_year" => 2026, "month_segment" => "early", "party_size_total" => 2, "adults" => 2 })
      else
        interpretation(slots: { "days" => 2, "nights" => 1 })
      end
    end

    result = described_class.new(hotel: hotel, message: "can i book for early june? for 2 people", phone: "+60123456789", identity_mode: :known_contact).call

    expect(result).to be_success
    expect(result.payload[:reply_message]).to include("How many days and nights")

    follow_up = described_class.new(hotel: hotel, message: "2 days 1 night", phone: "+60123456789", identity_mode: :known_contact).call
    expect(follow_up.payload[:reply_message]).to include("For 2 people")
  end

  def interpretation(slots: {})
    {
      "intent" => "booking_search",
      "topic" => "booking_search",
      "confidence" => 1.0,
      "slots" => slots,
      "tool_hints" => ["search_booking_options"],
      "conversation_signals" => {
        "is_reset" => false,
        "is_resume" => false,
        "is_correction" => false,
        "starts_new_booking_branch" => false
      }
    }
  end
end
