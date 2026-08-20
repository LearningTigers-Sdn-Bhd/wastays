require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Turn::ResponsePersister do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:prospect) { create(:prospect, hotel: hotel) }
  let(:conversation_state) { create(:prospect_conversation_state, prospect: prospect) }

  it "runs messenger, persists state, records outbound message, and builds public payload" do
    payload = described_class.new(hotel: hotel).persist_response(
      prospect: prospect,
      conversation_state: conversation_state,
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
    expect(conversation_state.reload.pending_question).to be_nil
  end

  it "carries a domain result's escalation flag into the payload" do
    conversation_state = create(:prospect_conversation_state, prospect: prospect)

    payload = described_class.new(hotel: hotel).persist_domain_response(
      prospect: prospect,
      conversation_state: conversation_state,
      domain_result: {
        slots_payload: {},
        reply_type: nil,
        extra_context: { message: "Unable right now" },
        needs_human_support: true
      }
    )

    expect(payload[:reply_message]).to eq("Unable right now")
    expect(payload[:needs_human_support]).to be(true)
    expect(prospect.prospect_messages.where(direction: "outbound").last.body).to eq("Unable right now")
  end
end

RSpec.describe AiConcierge::Orchestration::Turn::ResponsePersister, "conversation threading" do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:prospect) { create(:prospect, hotel: hotel) }
  let(:conversation) { create(:conversation, :whatsapp, hotel: hotel, prospect: prospect) }
  let(:conversation_state) { create(:prospect_conversation_state, prospect: prospect) }

  def persist(persister)
    persister.persist_response(
      prospect: prospect,
      conversation_state: conversation_state,
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

  describe "the hotel's voice" do
    def persist_with(message)
      persist(described_class.new(hotel: hotel, conversation: conversation, message: message))
    end

    def last_body = prospect.prospect_messages.where(direction: "outbound").last.body

    it "sends what the stylist wrote and remembers the language it was in" do
      styled = "Selamat datang ke #{hotel.name}! Saya boleh bantu dengan tempahan."
      stub_concierge_stylist(text: styled, language: "ms")

      payload = persist_with("ada bilik kosong?")

      expect(payload[:reply_message]).to eq(styled)
      expect(last_body).to eq(styled)
      expect(conversation.reload.language).to eq("ms")
    end

    # The one that matters: a rewrite the verifier rejects must never reach the
    # guest, and the template says the same thing correctly.
    it "sends the template when the rewrite changed something the guest could act on" do
      allow_any_instance_of(AiConcierge::Agents::ReplyStylist).to receive(:call).and_return(
        AiConcierge::Agents::ReplyStylist::Styled.new(text: "Book at https://elsewhere.test now!", language: "ms")
      )

      payload = persist_with("boleh tempah?")

      expect(payload[:reply_message]).to include("Hello, welcome to")
      expect(last_body).to include("Hello, welcome to")
    end

    # What the guest wrote in is a fact about the guest, not about whether this
    # particular rewrite came back usable.
    it "still remembers the language when the rewrite is rejected" do
      allow_any_instance_of(AiConcierge::Agents::ReplyStylist).to receive(:call).and_return(
        AiConcierge::Agents::ReplyStylist::Styled.new(text: "Book at https://elsewhere.test now!", language: "ms")
      )

      persist_with("boleh tempah?")

      expect(conversation.reload.language).to eq("ms")
    end

    it "sends the template when the stylist fails outright" do
      allow_any_instance_of(AiConcierge::Agents::ReplyStylist).to receive(:call)
        .and_raise(AiConcierge::Agents::ReplyStylist::ReplyStylistError, "timed out")

      expect(persist_with("hello there")[:reply_message]).to include("Hello, welcome to")
    end

    it "does not reach for the stylist when the guest answered with a bare number" do
      expect_any_instance_of(AiConcierge::Agents::ReplyStylist).not_to receive(:call)

      persist_with("2")
    end
  end
end
