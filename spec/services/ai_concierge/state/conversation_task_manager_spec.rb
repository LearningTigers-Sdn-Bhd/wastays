require "rails_helper"

RSpec.describe AiConcierge::State::ConversationTaskManager do
  it "normalizes legacy active state into a v2 booking task" do
    branch = { "branch_id" => "branch-1", "target_month" => 8 }

    payload = described_class.new(slots_payload: { "active" => branch, "paused_flows" => [] }).payload

    expect(payload["state_version"]).to eq(2)
    expect(payload["booking_task"]["branch"]["target_month"]).to eq(8)
    expect(payload).not_to have_key("active")
    expect(payload).not_to have_key("paused_flows")
  end

  it "normalizes legacy paused booking flow into a suspended v2 booking task" do
    branch = { "branch_id" => "branch-1", "suggested_options" => [ { "room_type_name" => "Deluxe Room" } ] }
    payload = described_class.new(slots_payload: {
      "paused_flows" => [
        {
          "topic" => "booking_search",
          "pending_question" => "select_option",
          "slots" => branch,
          "updated_at" => Time.current.iso8601,
          "expires_at" => 30.minutes.from_now.iso8601
        }
      ]
    }).payload

    expect(payload.dig("booking_task", "status")).to eq("suspended")
    expect(payload.dig("booking_task", "pending_question")).to eq("select_option")
    expect(payload.dig("booking_task", "branch", "suggested_options")).to eq(branch["suggested_options"])
    expect(payload).not_to have_key("paused_flows")
  end

  it "suspends and resumes booking without losing confirmation candidate" do
    selected_option = { "selection_id" => "sel_1", "room_type_name" => "Deluxe Room" }
    branch = {
      "branch_id" => "branch-1",
      "target_month" => 8,
      "suggested_options" => [ { "room_type_name" => "Deluxe Room", "options" => [] } ],
      "confirmation_candidate" => selected_option,
      "selected_option" => selected_option
    }
    payload = described_class.new(slots_payload: {}).activate_booking(branch, pending_question: "confirm_selection")

    suspended = described_class.new(slots_payload: payload).suspend_booking_for_information(
      intent: "hotel_policy",
      topic: "hotel_policy",
      pending_question: "confirm_selection"
    )
    resumed_payload, resumed_task = described_class.new(slots_payload: suspended).resume_booking

    expect(suspended["booking_task"]["status"]).to eq("suspended")
    expect(resumed_task["pending_question"]).to eq("confirm_selection")
    expect(resumed_task.dig("branch", "confirmation_candidate")).to eq(selected_option)
    expect(resumed_payload["booking_task"]["status"]).to eq("waiting_for_confirmation")
  end

  it "does not resume expired suspended booking" do
    payload = described_class.new(slots_payload: {}).activate_booking({ "target_month" => 8 }, pending_question: "select_option")
    suspended = described_class.new(slots_payload: payload, now: 2.hours.ago).suspend_booking_for_information(
      intent: "hotel_information",
      topic: "hotel_faq",
      pending_question: "select_option"
    )

    _payload, resumed_task = described_class.new(slots_payload: suspended, now: Time.current).resume_booking

    expect(resumed_task).to be_nil
  end
end
