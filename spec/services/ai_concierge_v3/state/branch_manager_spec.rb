require "rails_helper"

RSpec.describe AiConciergeV3::State::BranchManager do
  it "pauses and resumes the active branch" do
    active_branch = { "branch_id" => SecureRandom.uuid, "target_month" => 7 }
    manager = described_class.new(slots_payload: { "active" => active_branch, "paused_flows" => [], "completed_booking_branches" => [] })

    paused = manager.pause_active(topic: "booking_search", pending_question: "select_option")
    resumed_payload, resumed_flow = described_class.new(slots_payload: paused).resume_latest

    expect(paused["active"]).to be_nil
    expect(resumed_flow["pending_question"]).to eq("select_option")
    expect(resumed_payload["active"]).to eq(active_branch)
  end
end
