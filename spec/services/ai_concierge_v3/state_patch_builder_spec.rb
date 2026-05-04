require "rails_helper"

RSpec.describe AiConciergeV3::StatePatchBuilder do
  it "normalizes the slots payload arrays" do
    patch = described_class.new(
      conversation_state: nil,
      slots_payload: { "active" => { "branch_id" => "1" } },
      active_topic: "booking_search",
      active_flow: "booking_search",
      pending_question: "guest_count",
      last_intent: "booking_search",
      last_action_name: "request_quote"
    ).call

    expect(patch[:slots_payload]["paused_flows"]).to eq([])
    expect(patch[:slots_payload]["completed_booking_branches"]).to eq([])
  end
end
