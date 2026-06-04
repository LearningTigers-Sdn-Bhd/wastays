require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Conversation::ControlHandler do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:prospect) { create(:prospect, hotel: hotel) }
  let(:conversation_state) { create(:prospect_conversation_state, prospect: prospect) }
  let(:response_persister) { AiConcierge::Orchestration::Conversation::ResponsePersister.new(hotel: hotel) }

  before do
    create(:property_policy, hotel: hotel)
  end

  it "cancels an active booking attempt without ending the conversation" do
    conversation_state.update!(active_flow: "booking_search")

    result = described_class.new(message: "changed my mind", response_persister: response_persister).handle(
      prospect: prospect,
      conversation_state: conversation_state,
      interpretation: interpretation
    )

    expect(result).to be_success
    expect(result.payload[:reply_message]).to include("start a new booking")
    expect(conversation_state.reload.flow_status).to eq("active")
  end

  it "requests end confirmation for an active booking flow" do
    conversation_state.update!(active_flow: "booking_search")

    result = described_class.new(message: "stop", response_persister: response_persister).handle(
      prospect: prospect,
      conversation_state: conversation_state,
      interpretation: interpretation
    )

    expect(result.payload[:reply_message]).to include("end the conversation")
    expect(conversation_state.reload.pending_question).to eq("confirm_to_end_conversation")
  end

  it "ends immediately for generic explicit end" do
    result = described_class.new(message: "bye", response_persister: response_persister).handle(
      prospect: prospect,
      conversation_state: conversation_state,
      interpretation: interpretation
    )

    expect(result.payload[:reply_message]).to eq("No problem, please let me know if you need anything.")
    expect(conversation_state.reload.flow_status).to eq("ended")
  end

  it "declines pending end confirmation on no" do
    conversation_state.update!(pending_question: "confirm_to_end_conversation")

    result = described_class.new(message: "no", response_persister: response_persister).handle(
      prospect: prospect,
      conversation_state: conversation_state,
      interpretation: interpretation(intent: "confirmation", slots: { "confirmation" => "no" })
    )

    expect(result.payload[:reply_message]).to eq("No problem, please let me know if you need anything.")
    expect(conversation_state.reload.flow_status).to eq("active")
  end

  it "builds max-turn response and marks the conversation ended" do
    result = described_class.new(message: "hello", response_persister: response_persister).max_turns_response(
      prospect: prospect,
      conversation_state: conversation_state
    )

    expect(result.payload[:needs_human_support]).to be(true)
    expect(result.payload[:reply_message]).to include("limit for this conversation")
    expect(conversation_state.reload.flow_status).to eq("ended")
  end

  def interpretation(intent: "greeting", slots: {})
    {
      "intent" => intent,
      "topic" => "general",
      "slots" => slots,
      "conversation_signals" => {
        "end_conversation" => false
      }
    }
  end
end
