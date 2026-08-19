require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Conversation::SessionLoader do
  let(:hotel) { create(:hotel, :with_ai_concierge) }

  it "resolves an existing prospect by public id inside a lock and records the inbound message" do
    prospect = create(:prospect, hotel: hotel, phone_number: "+60123456789")
    state = create(:prospect_conversation_state, prospect: prospect)
    locked = false

    expect_any_instance_of(Prospect).to receive(:with_lock).and_wrap_original do |original, *args, &block|
      locked = true
      original.call(*args, &block)
    ensure
      locked = false
    end

    described_class.new(hotel: hotel, message: "hello", prospect_public_id: prospect.public_id).with_locked_session do |session|
      expect(locked).to be(true)
      expect(session.prospect).to eq(prospect)
      expect(session.conversation_state).to eq(state)
    end

    expect(prospect.prospect_messages.last.body).to eq("hello")
  end

  it "creates a prospect from a valid phone when one does not exist" do
    session_prospect = nil

    described_class.new(hotel: hotel, message: "hello", phone: "+60123456789").with_locked_session do |session|
      session_prospect = session.prospect
    end

    expect(session_prospect.phone_number).to eq("+60123456789")
    expect(session_prospect.prospect_conversation_state).to be_present
  end

  it "raises not found for an unknown prospect public id" do
    expect {
      described_class.new(hotel: hotel, message: "hello", prospect_public_id: "missing").with_locked_session { nil }
    }.to raise_error(AiConcierge::ProspectNotFoundError, "Prospect not found")
  end

  it "reactivates ended conversation state when a new inbound message arrives" do
    prospect = create(:prospect, hotel: hotel)
    state = create(
      :prospect_conversation_state,
      prospect: prospect,
      flow_status: "ended",
      slots_payload: { "conversation" => { "status" => "ended", "ended_at" => 1.hour.ago.iso8601, "end_reason" => "user_ended" } }
    )

    described_class.new(hotel: hotel, message: "hello again", prospect_public_id: prospect.public_id).with_locked_session { nil }

    state.reload
    expect(state.flow_status).to eq("active")
    expect(state.slots_payload.dig("conversation", "status")).to eq("active")
    expect(state.slots_payload.dig("conversation", "ended_at")).to be_nil
    expect(state.slots_payload.dig("conversation", "end_reason")).to be_nil
  end

  it "detects max-turn state" do
    prospect = create(:prospect, hotel: hotel)
    state = create(:prospect_conversation_state, prospect: prospect, slots_payload: { "conversation" => { "turn_count" => 50 } })

    loader = described_class.new(hotel: hotel, message: "hello", prospect_public_id: prospect.public_id)

    expect(loader.max_turns_exceeded?(state)).to be(true)
  end
end

RSpec.describe AiConcierge::Orchestration::Conversation::SessionLoader, "conversation threading" do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:prospect) { create(:prospect, hotel: hotel, phone_number: "+60123456789") }

  def load_session(message: "hello", channel: nil)
    described_class.new(
      hotel: hotel,
      message: message,
      prospect_public_id: prospect.public_id,
      **(channel ? { channel: channel } : {})
    ).with_locked_session { |session| return session }
  end

  it "opens a conversation on the first message and files the message under it" do
    session = load_session

    expect(session.conversation).to be_present
    expect(session.conversation.hotel).to eq(hotel)
    expect(session.conversation.channel).to eq("whatsapp")
    expect(session.conversation).to be_open
    expect(prospect.prospect_messages.last.conversation).to eq(session.conversation)
  end

  it "records the guest as the author rather than leaving it to be guessed" do
    load_session

    expect(prospect.prospect_messages.last.sender_role).to eq("guest")
  end

  it "continues the same conversation on the next message" do
    first = load_session(message: "hello")
    second = load_session(message: "still here")

    expect(second.conversation).to eq(first.conversation)
    expect(first.conversation.messages.count).to eq(2)
  end

  it "starts a new conversation when the previous one was closed" do
    first = load_session(message: "hello")
    first.conversation.close!

    second = load_session(message: "back again")

    expect(second.conversation).not_to eq(first.conversation)
    expect(second.conversation).to be_open
    expect(prospect.conversations.count).to eq(2)
  end

  it "keeps a web thread separate from a whatsapp thread" do
    whatsapp = load_session(channel: "whatsapp")
    web = load_session(channel: "web")

    expect(web.conversation).not_to eq(whatsapp.conversation)
    expect(web.conversation.channel).to eq("web")
  end

  it "moves the conversation's last_message_at forward as the guest writes" do
    session = load_session

    expect(session.conversation.reload.last_message_at).to be_present
    expect(session.conversation.last_guest_message_at).to eq(session.conversation.last_message_at)
  end
end
