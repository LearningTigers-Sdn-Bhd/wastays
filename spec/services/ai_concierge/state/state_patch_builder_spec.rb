require "rails_helper"

RSpec.describe AiConcierge::State::StatePatchBuilder do
  it "normalizes slots payload into v2 task state" do
    patch = described_class.new(
      conversation_state: nil,
      slots_payload: { "active" => { "branch_id" => "1" } },
      active_topic: "booking_search",
      active_flow: "booking_search",
      pending_question: "guest_count"
    ).call

    expect(patch[:slots_payload]["state_version"]).to eq(2)
    expect(patch[:slots_payload]["booking_task"]).to be_present
    expect(patch[:slots_payload]["information_task"]).to be_present
    expect(patch[:slots_payload]["completed_booking_branches"]).to eq([])
    expect(patch[:slots_payload]).not_to have_key("active")
    expect(patch[:slots_payload]).not_to have_key("paused_flows")
  end

  it "updates user timestamp and conversation lifecycle metadata every turn" do
    conversation_state = create(:prospect_conversation_state, last_user_message_at: 1.hour.ago)
    now = Time.zone.parse("2026-05-06 10:30:00")

    patch = described_class.new(
      conversation_state: conversation_state,
      slots_payload: { "conversation" => { "turn_count" => 2 } },
      active_topic: nil,
      active_flow: nil,
      pending_question: nil,
      now: now
    ).call

    expect(patch[:last_user_message_at]).to eq(now)
    expect(patch[:slots_payload].dig("conversation", "status")).to eq("active")
    expect(patch[:slots_payload].dig("conversation", "last_user_message_at")).to eq(now.iso8601)
    expect(patch[:slots_payload].dig("conversation", "turn_count")).to eq(3)
  end

  it "marks ended lifecycle metadata" do
    now = Time.zone.parse("2026-05-06 10:30:00")

    patch = described_class.new(
      conversation_state: nil,
      slots_payload: {},
      active_topic: nil,
      active_flow: nil,
      pending_question: nil,
      flow_status: "ended",
      end_reason: "user_ended",
      now: now
    ).call

    expect(patch[:slots_payload].dig("conversation", "status")).to eq("ended")
    expect(patch[:slots_payload].dig("conversation", "ended_at")).to eq(now.iso8601)
    expect(patch[:slots_payload].dig("conversation", "end_reason")).to eq("user_ended")
  end
end
