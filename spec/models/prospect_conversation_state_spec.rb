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

  it "normalizes non-hash slots_payload to an empty hash" do
    state = described_class.create!(prospect: create(:prospect), slots_payload: "bad")

    expect(state.slots_payload).to eq({})
  end
end
