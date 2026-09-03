require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Turn::GreetingHandler do
  let(:hotel) { create(:hotel) }
  let(:prospect) { create(:prospect, hotel: hotel) }
  let(:conversation_state) { create(:prospect_conversation_state, prospect: prospect) }

  def handle(message = "hello")
    described_class.new(message: message).call(conversation_state: conversation_state)
  end

  it "returns a greeting response without changing the conversation tasks" do
    original = AiConcierge::State::ConversationTaskManager.new(
      slots_payload: conversation_state.slots_payload
    ).payload
    conversation_state.update!(slots_payload: original)

    result = handle

    expect(result.reply_type).to eq(:greeting)
    expect(result.next_action.kind).to eq("none")
    expect(result.action_name).to be_nil
    expect(result.pending_question).to be_nil
    expect(result.slots_payload["booking_task"]).to eq(original["booking_task"])
    expect(result.slots_payload["information_task"]).to eq(original["information_task"])
    expect(result.slots_payload.dig("ui_task", "suggestion_group")).to eq("greeting")
  end

  it "does not capture a greeting during an active booking" do
    slots = AiConcierge::State::ConversationTaskManager.new(slots_payload: {}).activate_booking(
      AiConcierge::State::SlotMerger.empty_branch,
      pending_question: "booking_timing"
    )
    conversation_state.update!(slots_payload: slots, pending_question: "booking_timing")

    expect(handle).to be_nil
  end

  it "does not capture a greeting while a booking is suspended" do
    manager = AiConcierge::State::ConversationTaskManager.new(slots_payload: {})
    active = manager.activate_booking(
      AiConcierge::State::SlotMerger.empty_branch.merge("target_month" => 9),
      pending_question: "guest_count"
    )
    suspended = AiConcierge::State::ConversationTaskManager.new(slots_payload: active).suspend_booking_for_information(
      intent: "hotel_information",
      topic: "general_hotel_info",
      pending_question: "guest_count"
    )
    conversation_state.update!(slots_payload: suspended)

    expect(handle("hello again")).to be_nil
  end

  it "does not capture an answer to a hotel-information clarification" do
    slots = AiConcierge::State::ConversationTaskManager.new(slots_payload: {}).update_information_task(
      intent: "hotel_information",
      topic: "general_hotel_info",
      pending_question: "facility_opening_hours"
    )
    conversation_state.update!(slots_payload: slots)

    expect(handle).to be_nil
  end

  it "does not capture a message with a greeting and another purpose" do
    expect(handle("Hello, I want to book")).to be_nil
  end
end
