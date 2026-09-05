# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Turn::SecureInputHandler do
  let(:prospect) { create(:prospect) }
  let(:conversation_state) { create(:prospect_conversation_state, prospect: prospect, slots_payload: {}) }

  it "requests a confirmation code while the secure lookup is active" do
    slots_payload = AiConcierge::State::ConversationTaskManager.new(slots_payload: {})
      .request_existing_booking_code
    conversation_state.update!(slots_payload: slots_payload)

    result = described_class.new.call(conversation_state: conversation_state)

    expect(result.reply_type).to eq(:ask_existing_booking_confirmation_code)
    expect(result.pending_question).to eq("confirmation_code")
    expect(result.slots_payload).to eq(slots_payload)
  end

  it "does nothing when the conversation is not waiting for secure input" do
    expect(described_class.new.call(conversation_state: conversation_state)).to be_nil
  end

  it "ignores secure input that belongs to another conversation" do
    conversation = create(:conversation, prospect: prospect, channel: "web")
    slots_payload = AiConcierge::State::ConversationTaskManager.new(slots_payload: {})
      .request_existing_booking_code(conversation_id: conversation.id + 1)
    conversation_state.update!(slots_payload: slots_payload)

    result = described_class.new(conversation: conversation).call(conversation_state: conversation_state)

    expect(result).to be_nil
  end
end
