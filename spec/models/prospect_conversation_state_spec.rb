require "rails_helper"

RSpec.describe ProspectConversationState, type: :model do
  it "is valid with default factory values" do
    expect(build(:prospect_conversation_state)).to be_valid
  end

  it "requires a unique prospect" do
    prospect = create(:prospect)
    create(:prospect_conversation_state, prospect: prospect)

    duplicate = build(:prospect_conversation_state, prospect: prospect)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:prospect_id]).to include("has already been taken")
  end

  it "restricts flow_status to supported values" do
    state = build(:prospect_conversation_state, flow_status: "unknown")

    expect(state).not_to be_valid
    expect(state.errors[:flow_status]).to include("is not included in the list")
  end

  it "resets everything a finished thread left behind" do
    state = create(
      :prospect_conversation_state,
      :awaiting_option_selection,
      flow_status: "paused",
      last_user_message_at: 1.hour.ago
    )

    state.reset!

    expect(state.slots_payload).to eq({})
    expect(state.pending_question).to be_nil
    expect(state.active_topic).to be_nil
    expect(state.active_flow).to be_nil
    expect(state.flow_status).to eq("active")
  end

  it "normalizes non-hash slots_payload to an empty hash" do
    state = described_class.create!(prospect: create(:prospect), slots_payload: "bad")

    expect(state.slots_payload).to eq({})
  end
end
