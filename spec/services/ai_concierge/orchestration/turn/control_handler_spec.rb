require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Turn::ControlHandler do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:prospect) { create(:prospect, hotel: hotel) }
  let(:conversation_state) { create(:prospect_conversation_state, prospect: prospect) }
  let(:conversation) { create(:conversation, :whatsapp, hotel: hotel, prospect: prospect) }
  let(:response_persister) { AiConcierge::Orchestration::Turn::ResponsePersister.new(hotel: hotel, conversation: conversation) }

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

    expect(result.payload[:reply_message]).to include("Would you like to end this chat?")
    expect(conversation_state.reload.pending_question).to eq("confirm_to_end_conversation")
  end

  it "ends immediately for generic explicit end" do
    result = described_class.new(message: "bye", response_persister: response_persister).handle(
      prospect: prospect,
      conversation_state: conversation_state,
      interpretation: interpretation
    )

    expect(result.payload[:reply_message]).to eq("Thank you for chatting with us. Message us any time.")
    expect(conversation_state.reload.flow_status).to eq("ended")
  end

  it "declines pending end confirmation on no" do
    conversation_state.update!(pending_question: "confirm_to_end_conversation")

    result = described_class.new(message: "no", response_persister: response_persister).handle(
      prospect: prospect,
      conversation_state: conversation_state,
      interpretation: interpretation(intent: "confirmation", slots: { "confirmation" => "no" })
    )

    expect(result.payload[:reply_message]).to eq("No problem, I'm here if you need anything else.")
    expect(conversation_state.reload.flow_status).to eq("active")
  end

  # "No thanks" answering "would you like to end this chat?" is a refusal to
  # end, even though the same words on any other turn are a goodbye.
  it "reads a polite no as declining rather than as another goodbye" do
    conversation_state.update!(pending_question: "confirm_to_end_conversation")

    result = described_class.new(message: "no thanks", response_persister: response_persister).handle(
      prospect: prospect,
      conversation_state: conversation_state,
      interpretation: {}
    )

    expect(conversation_state.reload.flow_status).to eq("active")
    expect(result.payload[:reply_message]).to include("No problem")
  end

  # A question asked on the way out is still a question. It used to be met with
  # "no problem" and dropped.
  it "hands an answer that is neither yes nor no to the model" do
    conversation_state.update!(pending_question: "confirm_to_end_conversation")

    result = described_class.new(message: "what time is check in?", response_persister: response_persister).handle(
      prospect: prospect,
      conversation_state: conversation_state,
      interpretation: {}
    )

    expect(result).to be_nil
  end

  it "ends the conversation on a yes read straight from the message" do
    conversation_state.update!(pending_question: "confirm_to_end_conversation")

    described_class.new(message: "yes please", response_persister: response_persister).handle(
      prospect: prospect,
      conversation_state: conversation_state,
      interpretation: {}
    )

    expect(conversation_state.reload.flow_status).to eq("ended")
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

  it "force ends a wait-time control message without booking progress" do
    result = described_class.new(message: "codename: wait-time-end", response_persister: response_persister).wait_time_end_response(
      prospect: prospect,
      conversation_state: conversation_state
    )

    conversation_state.reload
    expect(result.payload[:reply_message]).to eq("Thank you for reaching out. Please come back again.")
    expect(conversation_state.flow_status).to eq("ended")
    expect(conversation_state.slots_payload.dig("conversation", "end_reason")).to eq("wait_time_end")
  end

  it "force ends a wait-time control message with booking progress" do
    conversation_state.update!(active_flow: "booking_search")

    result = described_class.new(message: "codename: wait-time-end", response_persister: response_persister).wait_time_end_response(
      prospect: prospect,
      conversation_state: conversation_state
    )

    conversation_state.reload
    expect(result.payload[:reply_message]).to eq("It seems you are no longer making a booking quotation. Thank you for reaching out. Please come back again.")
    expect(conversation_state.flow_status).to eq("ended")
    expect(conversation_state.active_flow).to be_nil
    expect(conversation_state.slots_payload.dig("booking_task", "status")).to eq("idle")
    expect(conversation_state.slots_payload.dig("conversation", "end_reason")).to eq("wait_time_end")
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
