require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Turn::ExistingBookingSupportHandler do
  let(:hotel) { create(:hotel) }
  let(:prospect) { create(:prospect, hotel: hotel, phone_number: nil) }
  let(:conversation) { create(:conversation, hotel: hotel, prospect: prospect, channel: "web") }
  let(:state) { create(:prospect_conversation_state, prospect: prospect) }

  it "offers the portal for an existing cancellation" do
    result = described_class.new(message: "Cancel my booking", conversation: conversation).call(conversation_state: state)

    expect(result.reply_type).to eq(:existing_booking_cancellation_portal)
    expect(result.slots_payload.dig("existing_booking_task", "status")).to eq("portal_offered")
  end

  it "asks for the secure code after the guest accepts the portal link" do
    offered = AiConcierge::State::ConversationTaskManager.new(slots_payload: {}).offer_existing_booking_portal
    state.update!(slots_payload: offered)

    result = described_class.new(message: "Send my login link", conversation: conversation).call(conversation_state: state)

    expect(result.reply_type).to eq(:ask_existing_booking_confirmation_code)
    expect(result.slots_payload.dig("existing_booking_task", "status")).to eq("awaiting_confirmation_code")
  end

  it "does not intercept attempt cancellation after offering the portal" do
    offered = AiConcierge::State::ConversationTaskManager.new(slots_payload: {})
      .offer_existing_booking_portal(conversation_id: conversation.id)
    state.update!(slots_payload: offered)

    result = described_class.new(
      message: "Never mind, cancel the booking attempt",
      conversation: conversation
    ).call(conversation_state: state)

    expect(result).to be_nil
  end

  it "accepts a visible staff request after a portal link was sent" do
    linked = AiConcierge::State::ConversationTaskManager.new(slots_payload: {})
      .offer_existing_booking_portal(conversation_id: conversation.id)
    linked = AiConcierge::State::ConversationTaskManager.new(slots_payload: linked).record_magic_link_sent
    state.update!(slots_payload: linked)

    result = described_class.new(
      message: "Please ask the hotel team to help with my booking.",
      conversation: conversation
    ).call(conversation_state: state)

    expect(result.reply_type).to eq(:booking_support_requested)
    expect(result.needs_human_support).to be(true)
  end

  it "offers staff for a date change in an existing-booking context" do
    offered = AiConcierge::State::ConversationTaskManager.new(slots_payload: {}).offer_existing_booking_portal
    state.update!(slots_payload: offered)

    result = described_class.new(message: "Change my check-in date", conversation: conversation).call(conversation_state: state)

    expect(result.reply_type).to eq(:unsupported_date_change)
    expect(result.slots_payload.dig("ui_task", "suggestion_group")).to eq("unsupported_change")
  end

  it "requests staff immediately when booking-change escalation is enabled" do
    create(:hotel_guest_contact, hotel: hotel, escalation_triggers: [ "booking_change" ])

    result = described_class.new(
      message: "Change my booking check-in date",
      conversation: conversation
    ).call(conversation_state: state)

    expect(result.reply_type).to be_nil
    expect(result.needs_human_support).to be(true)
    expect(result.extra_context).to include(
      escalation_trigger: "booking_change",
      message: include("asked a team member")
    )
  end

  it "requests staff immediately for an enabled guest-specific payment issue" do
    create(:hotel_guest_contact, hotel: hotel, escalation_triggers: [ "payment_question" ])

    result = described_class.new(
      message: "Dispute the wrong charge on my booking",
      conversation: conversation
    ).call(conversation_state: state)

    expect(result.needs_human_support).to be(true)
    expect(result.extra_context[:escalation_trigger]).to eq("payment_question")
  end

  it "leaves a date revision in an active new-booking search" do
    active = AiConcierge::State::ConversationTaskManager.new(slots_payload: {}).activate_booking(
      { "check_in" => "2026-09-10" },
      pending_question: "booking_timing"
    )
    state.update!(slots_payload: active)

    result = described_class.new(message: "Change my check-in date", conversation: conversation).call(conversation_state: state)

    expect(result).to be_nil
  end

  it "routes a WhatsApp cancellation to staff without claiming success" do
    whatsapp = create(:conversation, :whatsapp, hotel: hotel, prospect: prospect)

    result = described_class.new(message: "Cancel my booking", conversation: whatsapp).call(conversation_state: state)

    expect(result.reply_type).to eq(:booking_cancellation_support_requested)
    expect(result.needs_human_support).to be(true)
  end
end
