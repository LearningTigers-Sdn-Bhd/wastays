require "rails_helper"

RSpec.describe AiConcierge::Orchestration::HotelKnowledge::StateHandler do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:prospect) { create(:prospect, hotel: hotel, phone_number: "+60123456789") }
  let(:branch) do
    {
      "branch_id" => "branch-1",
      "target_month" => 8,
      "target_year" => 2026,
      "confirmation_candidate" => { "selection_id" => "sel_1" }
    }
  end
  let(:slots_payload) do
    AiConcierge::State::ConversationTaskManager.new(slots_payload: {}).activate_booking(branch, pending_question: "confirm_selection")
  end
  let(:conversation_state) { create(:prospect_conversation_state, prospect: prospect, pending_question: "confirm_selection", slots_payload: slots_payload) }

  it "updates information task without suspending booking when pause is false" do
    payload = described_class.new(
      conversation_state: conversation_state,
      interpretation: interpretation("hotel_information", "general_hotel_info"),
      message: "tell me about hotel",
      pause: false
    ).slots_payload

    expect(payload.dig("booking_task", "status")).to eq("waiting_for_confirmation")
    expect(payload.dig("booking_task", "suspended")).to be(false)
    expect(payload.dig("information_task", "intent")).to eq("hotel_information")
    expect(payload.dig("information_task", "last_question")).to eq("tell me about hotel")
  end

  it "stores a knowledge clarification separately from the booking question" do
    payload = described_class.new(
      conversation_state: conversation_state,
      interpretation: interpretation("hotel_information", "general_hotel_info"),
      message: "what hour do you open?",
      pause: false,
      pending_question: "opening_hours_subject",
      clarification_context: { "choices" => [ "check-in", "facility" ] }
    ).slots_payload

    expect(payload.dig("booking_task", "pending_question")).to eq("confirm_selection")
    expect(payload.dig("information_task", "status")).to eq("waiting_for_guest")
    expect(payload.dig("information_task", "pending_question")).to eq("opening_hours_subject")
    expect(payload.dig("information_task", "context", "choices")).to eq([ "check-in", "facility" ])
  end

  it "suspends the active booking and updates information task when pause is true" do
    payload = described_class.new(
      conversation_state: conversation_state,
      interpretation: interpretation("hotel_policy", "hotel_policy"),
      message: "what time is check in?",
      pause: true
    ).slots_payload

    expect(payload.dig("booking_task", "status")).to eq("suspended")
    expect(payload.dig("booking_task", "pending_question")).to eq("confirm_selection")
    expect(payload.dig("information_task", "intent")).to eq("hotel_policy")
  end

  it "suspends a provided merged active branch" do
    active_branch = { "branch_id" => "branch-2", "target_month" => 9, "target_year" => 2026 }
    empty_state = create(:prospect_conversation_state, prospect: prospect, slots_payload: {})

    payload = described_class.new(
      conversation_state: empty_state,
      interpretation: interpretation("hotel_policy", "hotel_policy"),
      message: "early september, what time is check in?",
      pause: true,
      active_branch: active_branch
    ).slots_payload

    expect(payload.dig("booking_task", "status")).to eq("suspended")
    expect(payload.dig("booking_task", "branch", "target_month")).to eq(9)
    expect(payload.dig("information_task", "last_question")).to eq("early september, what time is check in?")
  end

  def interpretation(intent, topic)
    { "intent" => intent, "topic" => topic }
  end
end
