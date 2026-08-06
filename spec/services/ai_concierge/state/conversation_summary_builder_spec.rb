require "rails_helper"

RSpec.describe AiConcierge::State::ConversationSummaryBuilder do
  it "builds a compact v2 task summary for the interpreter" do
    prospect = create(:prospect)
    create(:prospect_message, prospect: prospect, direction: "inbound", body: "I want to book")
    create(:prospect_message, prospect: prospect, direction: "outbound", body: "Please choose one of the room options.")
    branch = {
      "target_month" => 8,
      "target_year" => 2026,
      "suggested_options" => [
        {
          "room_type_name" => "Deluxe Room",
          "options" => [
            {
              "position" => 1,
              "selection_id" => "sel_1",
              "check_in" => "2026-08-01",
              "check_out" => "2026-08-03"
            }
          ]
        }
      ],
      "confirmation_candidate" => {
        "selection_id" => "sel_1",
        "room_type_name" => "Deluxe Room",
        "check_in" => "2026-08-01",
        "check_out" => "2026-08-03",
        "rate_plans" => [
          { "name" => "Standard Rate" },
          { "name" => "Non-Refundable Rate" }
        ]
      },
      "selected_option" => {
        "selection_id" => "sel_1",
        "room_type_name" => "Deluxe Room",
        "check_in" => "2026-08-01",
        "check_out" => "2026-08-03",
        "selected_rate_plan" => { "name" => "Standard Rate" },
        "rate_plans" => [
          { "name" => "Standard Rate" },
          { "name" => "Non-Refundable Rate" }
        ]
      }
    }
    slots_payload = AiConcierge::State::ConversationTaskManager.new(slots_payload: {}).activate_booking(branch, pending_question: "confirm_selection")
    slots_payload = AiConcierge::State::ConversationTaskManager.new(slots_payload: slots_payload).suspend_booking_for_information(
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
    expect(summary[:last_assistant_question]).to eq("Please choose one of the room options.")
    expect(summary.dig(:booking_task, :shown_options)).to eq([
      {
        room_type_name: "Deluxe Room",
        options: [
          {
            position: 1,
            selection_id: "sel_1",
            check_in: "2026-08-01",
            check_out: "2026-08-03"
          }
        ]
      }
    ])
    expect(summary.dig(:booking_task, :rate_plan_options)).to eq([ "Standard Rate", "Non-Refundable Rate" ])
    expect(summary.dig(:booking_task, :selected_option_summary)).to eq(
      room_type_name: "Deluxe Room",
      check_in: "2026-08-01",
      check_out: "2026-08-03",
      selected_rate_plan_name: "Standard Rate"
    )
    expect(summary.dig(:information_task, :last_intent)).to eq("hotel_policy")
    expect(summary).not_to have_key(:active_branch)
    expect(summary).not_to have_key(:paused_flows_count)
  end

  it "does not expose stale options or rate plans after downstream state is cleared" do
    prospect = create(:prospect)
    stale_branch = {
      "target_month" => 8,
      "target_year" => 2026,
      "suggested_options" => [ { "room_type_name" => "Deluxe Room", "options" => [ { "position" => 1 } ] } ],
      "selected_option" => {
        "room_type_name" => "Deluxe Room",
        "check_in" => "2026-08-01",
        "check_out" => "2026-08-03",
        "selected_rate_plan" => { "name" => "Standard Rate" },
        "rate_plans" => [ { "name" => "Standard Rate" } ]
      },
      "selected_rate_plan_id" => 1,
      "selected_rate_plan_name" => "Standard Rate"
    }
    cleared_branch = AiConcierge::State::SlotMerger.new(
      active_branch: stale_branch,
      slots: { "target_month" => 9 },
      pending_question: nil,
      message: "september"
    ).call
    slots_payload = AiConcierge::State::ConversationTaskManager.new(slots_payload: {}).activate_booking(cleared_branch, pending_question: "duration")
    state = create(:prospect_conversation_state, prospect: prospect, slots_payload: slots_payload)

    summary = described_class.new(conversation_state: state).call

    expect(summary.dig(:booking_task, :has_suggested_options)).to be(false)
    expect(summary.dig(:booking_task, :has_selected_option)).to be(false)
    expect(summary.dig(:booking_task, :shown_options)).to eq([])
    expect(summary.dig(:booking_task, :rate_plan_options)).to eq([])
    expect(summary.dig(:booking_task, :selected_option_summary)).to be_nil
  end
end
