require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Turn::ResponsePersister do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:prospect) { create(:prospect, hotel: hotel) }
  let(:conversation_state) { create(:prospect_conversation_state, prospect: prospect) }
  let(:conversation) { create(:conversation, :whatsapp, hotel: hotel, prospect: prospect) }

  it "runs messenger, persists state, records outbound message, and builds public payload" do
    payload = described_class.new(hotel: hotel, conversation: conversation).persist_response(
      prospect: prospect,
      conversation_state: conversation_state,
      slots_payload: conversation_state.slots_payload,
      reply_type: :ask_duration,
      active_topic: nil,
      active_flow: nil,
      pending_question: nil,
      action_name: nil
    )

    expect(payload[:reply_message]).to eq("How many days and nights will you be staying?")
    expect(payload[:prospect_public_id]).to eq(prospect.public_id)
    expect(payload).not_to have_key(:next_action)
    expect(payload).not_to have_key(:sales_task)
    expect(prospect.prospect_messages.where(direction: "outbound").last.body).to eq(payload[:reply_message])
    expect(conversation_state.reload.pending_question).to be_nil
  end

  it "carries a domain result's escalation flag into the payload" do
    conversation_state = create(:prospect_conversation_state, prospect: prospect)

    payload = described_class.new(hotel: hotel, conversation: conversation).persist_domain_response(
      prospect: prospect,
      conversation_state: conversation_state,
      domain_result: AiConcierge::Orchestration::Core::DomainResponse.new(
        slots_payload: {},
        extra_context: { message: "Unable right now" },
        needs_human_support: true
      )
    )

    expect(payload[:reply_message]).to eq("Unable right now")
    expect(payload[:needs_human_support]).to be(true)
    expect(prospect.prospect_messages.where(direction: "outbound").last.body).to eq("Unable right now")
  end

  # The flag used to travel out in the payload and stop there, so on the web
  # chat -- where there is no relay to interpret it -- a guest whose quote
  # failed reached nobody at all.
  it "puts a thread that needs a person in front of staff" do
    described_class.new(hotel: hotel, conversation: conversation).persist_domain_response(
      prospect: prospect,
      conversation_state: conversation_state,
      domain_result: AiConcierge::Orchestration::Core::DomainResponse.new(
        slots_payload: {},
        extra_context: { message: "Unable right now" },
        needs_human_support: true
      )
    )

    expect(conversation.reload.human_requested_at).to be_present
    expect(conversation.mode).to eq("bot")
  end

  it "leaves the thread alone when the reply does not need one" do
    described_class.new(hotel: hotel, conversation: conversation).persist_response(
      prospect: prospect,
      conversation_state: conversation_state,
      slots_payload: conversation_state.slots_payload,
      reply_type: :ask_duration,
      active_topic: nil,
      active_flow: nil,
      pending_question: nil,
      action_name: nil
    )

    expect(conversation.reload.human_requested_at).to be_nil
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
      reply_type: :ask_duration,
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

  # The guest's clock is what WhatsApp's 24-hour reply window is measured
  # from, so the bot answering must never look like the guest writing.
  it "advances last_message_at but not last_guest_message_at" do
    conversation.update!(last_guest_message_at: 3.hours.ago)

    persist(described_class.new(hotel: hotel, conversation: conversation))

    conversation.reload
    expect(conversation.last_message_at).to be_present
    expect(conversation.last_guest_message_at).to be_within(1.second).of(3.hours.ago)
  end

  describe "the hotel's voice" do
    def persist_with(message)
      persist(described_class.new(hotel: hotel, conversation: conversation, message: message))
    end

    def last_body = prospect.prospect_messages.where(direction: "outbound").last.body

    it "sends what the stylist wrote and remembers the language it was in" do
      styled = "Berapa hari dan malam anda akan menginap?"
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
        AiConcierge::Agents::ReplyStylist::Styled.new(text: "Book at https://elsewhere.test now!", language: "ms", guest_language: "ms")
      )

      payload = persist_with("boleh tempah?")

      expect(payload[:reply_message]).to eq("How many days and nights will you be staying?")
      expect(last_body).to eq("How many days and nights will you be staying?")
    end

    it "sends the greeting template when the stylist changes the hotel name" do
      changed = "Hello! Welcome to Another Hotel. I can help you find the right stay, check prices, " \
        "answer hotel questions, or access an existing booking. What can I help you with today?"
      stub_concierge_stylist(text: changed, language: "en")

      payload = described_class.new(hotel: hotel, conversation: conversation, message: "hello").persist_response(
        prospect: prospect,
        conversation_state: conversation_state,
        slots_payload: conversation_state.slots_payload,
        reply_type: :greeting,
        active_topic: nil,
        active_flow: nil,
        pending_question: nil,
        action_name: nil
      )

      expect(payload[:reply_message]).to include("Welcome to #{hotel.name}.")
      expect(payload[:reply_message]).not_to include("Another Hotel")
    end

    it "sends the template when the stylist changes a masked magic-link email" do
      stub_concierge_stylist(
        text: "Your secure login link is on its way to another@example.com.",
        language: "en"
      )

      payload = described_class.new(hotel: hotel, conversation: conversation, message: "send the link").persist_response(
        prospect: prospect,
        conversation_state: conversation_state,
        slots_payload: conversation_state.slots_payload,
        reply_type: :magic_link_sent,
        active_topic: nil,
        active_flow: nil,
        pending_question: nil,
        action_name: nil,
        extra_context: {
          masked_email: "j•••@example.com",
          protected_names: [ "j•••@example.com" ]
        }
      )

      expect(payload[:reply_message]).to include("j•••@example.com")
      expect(payload[:reply_message]).not_to include("another@example.com")
    end

    # What the guest wrote in is a fact about the guest, not about whether this
    # particular rewrite came back usable.
    it "still remembers the language when the rewrite is rejected" do
      allow_any_instance_of(AiConcierge::Agents::ReplyStylist).to receive(:call).and_return(
        AiConcierge::Agents::ReplyStylist::Styled.new(text: "Book at https://elsewhere.test now!", language: "ms", guest_language: "ms")
      )

      persist_with("boleh tempah?")

      expect(conversation.reload.language).to eq("ms")
    end

    # The live bug this pair was written for: an English thread that answered
    # "yes" in Malay. The model reported a language it had not been given any
    # reason to write in, the thread recorded that report as fact, and from
    # then on every message too short to carry a language of its own was
    # answered in Malay -- because the fallback the model was handed had become
    # Malay, and nothing existed that could hand it back.
    it "does not take the model's word for what language the thread is in" do
      stub_concierge_stylist(text: "Berapa hari?", language: "ms", guest_language: nil)

      payload = persist_with("do you have any rooms free?")

      expect(conversation.reload.reply_language).to eq("en")
      expect(payload[:reply_message]).to eq("How many days and nights will you be staying?")
      expect(last_body).not_to eq("Berapa hari?")
    end

    it "follows the guest back to English once they write it" do
      conversation.update!(language: "ms")
      stub_concierge_stylist(text: "How many days and nights will you be staying?", language: "en", guest_language: "en")

      payload = persist_with("actually, do you have any rooms free?")

      expect(conversation.reload.language).to eq("en")
      expect(payload[:reply_message]).to eq("How many days and nights will you be staying?")
    end

    it "sends the template when the stylist fails outright" do
      allow_any_instance_of(AiConcierge::Agents::ReplyStylist).to receive(:call)
        .and_raise(AiConcierge::Agents::ReplyStylist::ReplyStylistError, "timed out")

      expect(persist_with("hello there")[:reply_message]).to eq("How many days and nights will you be staying?")
    end

    it "does not reach for the stylist when the guest answered with a bare number" do
      expect_any_instance_of(AiConcierge::Agents::ReplyStylist).not_to receive(:call)

      persist_with("2")
    end

    it "does not pass an English hotel-knowledge reply through the general stylist" do
      expect_any_instance_of(AiConcierge::Agents::ReplyStylist).not_to receive(:call)

      payload = described_class.new(hotel: hotel, conversation: conversation, message: "what time is check in?").persist_response(
        prospect: prospect,
        conversation_state: conversation_state,
        slots_payload: conversation_state.slots_payload,
        reply_type: :hotel_policy,
        active_topic: nil,
        active_flow: nil,
        pending_question: nil,
        action_name: nil,
        extra_context: {
          result: { "answer" => "You can check in from 3:00 PM." },
          knowledge_reply: true,
          guest_language: "en"
        }
      )

      expect(payload[:reply_message]).to eq("You can check in from 3:00 PM.")
      expect(last_body).to eq("You can check in from 3:00 PM.")
      expect(conversation.reload.language).to eq("en")
    end
  end
end
