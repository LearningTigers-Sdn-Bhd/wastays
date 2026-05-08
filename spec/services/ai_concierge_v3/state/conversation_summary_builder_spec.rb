require "rails_helper"

RSpec.describe AiConciergeV3::State::ConversationSummaryBuilder do
  it "builds a compact v2 task summary for the interpreter" do
    prospect = create(:prospect)
    branch = {
      "target_month" => 8,
      "target_year" => 2026,
      "suggested_options" => [ { "room_type_name" => "Deluxe Room", "options" => [] } ],
      "confirmation_candidate" => { "selection_id" => "sel_1" },
      "selected_option" => { "selection_id" => "sel_1" }
    }
    slots_payload = AiConciergeV3::State::ConversationTaskManager.new(slots_payload: {}).activate_booking(branch, pending_question: "confirm_selection")
    slots_payload = AiConciergeV3::State::ConversationTaskManager.new(slots_payload: slots_payload).suspend_booking_for_information(
      intent: "hotel_policy",
      topic: "hotel_policy",
      pending_question: "confirm_selection"
    )
    state = create(:prospect_conversation_state, prospect: prospect, slots_payload: slots_payload)

    summary = described_class.new(conversation_state: state).call

    expect(summary.dig(:booking_task, :status)).to eq("suspended")
    expect(summary.dig(:booking_task, :pending_question)).to eq("confirm_selection")
    expect(summary.dig(:booking_task, :has_suggested_options)).to be(true)
    expect(summary.dig(:booking_task, :has_confirmation_candidate)).to be(true)
    expect(summary.dig(:information_task, :last_intent)).to eq("hotel_policy")
    expect(summary).not_to have_key(:active_branch)
    expect(summary).not_to have_key(:paused_flows_count)
  end
end
