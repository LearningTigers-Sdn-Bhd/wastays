require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Conversation::ResponsePersister do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:prospect) { create(:prospect, hotel: hotel) }
  let(:conversation_state) { create(:prospect_conversation_state, prospect: prospect) }

  it "runs messenger, persists state, records outbound message, and builds public payload" do
    payload = described_class.new(hotel: hotel).persist_response(
      prospect: prospect,
      conversation_state: conversation_state,
      interpretation: { "intent" => "greeting" },
      slots_payload: conversation_state.slots_payload,
      reply_type: :greeting,
      active_topic: nil,
      active_flow: nil,
      pending_question: nil,
      action_name: nil
    )

    expect(payload[:reply_message]).to include("Hello, welcome to")
    expect(payload[:prospect_public_id]).to eq(prospect.public_id)
    expect(prospect.prospect_messages.where(direction: "outbound").last.body).to eq(payload[:reply_message])
    expect(conversation_state.reload.last_intent).to eq("greeting")
  end

  it "preserves direct payload shape while adding prospect public id" do
    payload = described_class.new(hotel: hotel).public_direct_payload(
      { reply_message: "Unable right now", needs_human_support: true, action_name: nil },
      prospect
    )

    expect(payload).to eq(
      reply_message: "Unable right now",
      needs_human_support: true,
      action_name: nil,
      prospect_public_id: prospect.public_id
    )
  end
end

RSpec.describe AiConcierge::Orchestration::Conversation::ResponsePersister, "conversation threading" do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:prospect) { create(:prospect, hotel: hotel) }
  let(:conversation) { create(:conversation, :whatsapp, hotel: hotel, prospect: prospect) }
  let(:conversation_state) { create(:prospect_conversation_state, prospect: prospect) }

  def persist(persister)
    persister.persist_response(
      prospect: prospect,
      conversation_state: conversation_state,
      interpretation: { "intent" => "greeting" },
      slots_payload: conversation_state.slots_payload,
      reply_type: :greeting,
      active_topic: nil,
      active_flow: nil,
      pending_question: nil,
      action_name: nil
    )
  end

  it "files the bot's reply under the conversation it was given" do
    persist(described_class.new(hotel: hotel, conversation: conversation))

    message = prospect.prospect_messages.where(direction: "outbound").last
    expect(message.conversation).to eq(conversation)
  end

  it "names the bot as the author instead of relying on the direction default" do
    persist(described_class.new(hotel: hotel, conversation: conversation))

    expect(prospect.prospect_messages.where(direction: "outbound").last.sender_role).to eq("bot")
  end

  it "advances last_message_at but not last_guest_message_at" do
    persist(described_class.new(hotel: hotel, conversation: conversation))

    conversation.reload
    expect(conversation.last_message_at).to be_present
    expect(conversation.last_guest_message_at).to be_nil
  end
end
