require "rails_helper"

RSpec.describe AiConciergeV3::Orchestration::TurnOrchestrator do
  let(:hotel) { create(:hotel, :with_ai_concierge) }

  before do
    create(:property_policy, hotel: hotel)
  end

  it "asks for duration after a month window is provided" do
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(slots: { "target_month" => 8, "target_year" => 2026, "month_segment" => "mid", "days" => 3, "nights" => 2 })
    )

    result = described_class.new(hotel: hotel, message: "mid august", phone: "+60123456789", identity_mode: :known_contact).call

    expect(result).to be_success
    expect(result.payload[:reply_message]).to include("How many days and nights")
    expect(result.payload[:action_name]).to eq("request_quote")
  end

  it "asks for booking timing when the interpreter invents a month for a vague message" do
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(slots: { "target_month" => 5, "target_year" => 2026, "month_segment" => "early", "adults" => 2, "children" => 0 })
    )

    result = described_class.new(hotel: hotel, message: "hello, is there any booking for 2 adults", phone: "+60123456789", identity_mode: :known_contact).call

    expect(result).to be_success
    expect(result.payload[:reply_message]).to include("what dates or month")
    expect(result.payload[:reply_message]).not_to include("May")
  end

  it "preserves people as a split clarification when the interpreter invents adults" do
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call) do |agent|
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

  it "asks for guest count when stay duration is provided without people total" do
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(slots: { "target_month" => 6, "target_year" => 2026, "month_segment" => "early", "days" => 4, "nights" => 3 })
    )

    result = described_class.new(hotel: hotel, message: "early june for 4 days", phone: "+60123456789", identity_mode: :known_contact).call

    expect(result).to be_success
    expect(result.payload[:reply_message]).to include("How many guests")
  end

  it "removes party_size_total if it is not explicitly in the message" do
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(slots: { "party_size_total" => 1 })
    )

    result = described_class.new(hotel: hotel, message: "i want to book", phone: "+60123456789", identity_mode: :known_contact).call

    # TransitionPolicy should ask for timing first, but we want to check that party_size_total didn't leak into state
    # Actually, let's check the persisted state or the response payload if possible.
    # The payload doesn't include the active branch directly, but we can verify the follow-up message.
    
    # If party_size_total was 1, it would ask for adult/child split or timing.
    # If party_size_total is nil, it will ask for timing.
    expect(result.payload[:reply_message]).to include("what dates or month")
    
    # Let's verify that it doesn't ask "For 1 people" in the next turn if we give it a month window.
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(slots: { "target_month" => 7, "target_year" => 2026, "month_segment" => "early" })
    )
    
    follow_up = described_class.new(hotel: hotel, message: "early july", phone: "+60123456789", identity_mode: :known_contact).call
    expect(follow_up.payload[:reply_message]).to include("How many days and nights")
    
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(slots: { "days" => 3, "nights" => 2 })
    )
    
    days_reply = described_class.new(hotel: hotel, message: "3 days", phone: "+60123456789", identity_mode: :known_contact).call
    expect(days_reply.payload[:reply_message]).to include("How many guests") # Not "For 1 people"
  end

  it "archives the active branch when ending the conversation and starts fresh on reactivation" do
    # 1. Start a booking flow
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(slots: { "target_month" => 7, "target_year" => 2026, "party_size_total" => 1 })
    )
    described_class.new(hotel: hotel, message: "book for 1 person in july", phone: "+60123456789", identity_mode: :known_contact).call

    # 2. End the conversation
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(conversation_signals: { "end_conversation" => true })
    )
    end_reply = described_class.new(hotel: hotel, message: "nevermind", phone: "+60123456789", identity_mode: :known_contact).call
    expect(end_reply.payload[:reply_message]).to include("let me know if you need anything")

    # 3. Reactivate with a greeting/booking request
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(slots: {}) # No slots, just "can i book"
    )
    reactivation_reply = described_class.new(hotel: hotel, message: "hello, can i make booking", phone: "+60123456789", identity_mode: :known_contact).call
    
    # It should ask for timing because the previous branch (with July) was archived
    expect(reactivation_reply.payload[:reply_message]).to include("what dates or month")
  end

  def interpretation(slots: {}, conversation_signals: {})
    {
      "intent" => "booking_search",
      "topic" => "booking_search",
      "confidence" => 1.0,
      "slots" => slots,
      "tool_hints" => [ "search_booking_options" ],
      "conversation_signals" => {
        "is_reset" => false,
        "is_resume" => false,
        "is_correction" => false,
        "starts_new_booking_branch" => false,
        "end_conversation" => false
      }.merge(conversation_signals)
    }
  end
end
