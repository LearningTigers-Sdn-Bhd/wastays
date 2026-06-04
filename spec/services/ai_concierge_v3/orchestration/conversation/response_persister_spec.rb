require "rails_helper"

RSpec.describe AiConciergeV3::Orchestration::Conversation::ResponsePersister do
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
