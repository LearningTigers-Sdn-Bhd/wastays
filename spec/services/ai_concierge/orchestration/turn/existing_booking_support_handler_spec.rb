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

  it "offers staff for a date change in an existing-booking context" do
    offered = AiConcierge::State::ConversationTaskManager.new(slots_payload: {}).offer_existing_booking_portal
    state.update!(slots_payload: offered)

    result = described_class.new(message: "Change my check-in date", conversation: conversation).call(conversation_state: state)

    expect(result.reply_type).to eq(:unsupported_date_change)
    expect(result.slots_payload.dig("ui_task", "suggestion_group")).to eq("unsupported_change")
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

  it "does not affect another chat channel" do
    whatsapp = create(:conversation, :whatsapp, hotel: hotel, prospect: prospect)

    result = described_class.new(message: "Cancel my booking", conversation: whatsapp).call(conversation_state: state)

    expect(result).to be_nil
  end
end
