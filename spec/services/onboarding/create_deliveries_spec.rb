# frozen_string_literal: true

require "rails_helper"

RSpec.describe Onboarding::CreateDeliveries do
  let(:hotel) { create(:hotel) }
  let(:submission) { create(:onboarding_submission, hotel:, submitted_by: create(:user, account: hotel.account)) }

  context "with a linked super agent" do
    let(:agent) { create(:user, :super_agent, email: "agent@example.com") }

    before { hotel.update!(created_by_user: agent) }

    it "adds an agent delivery when the hotel goes live" do
      described_class.for_owners(submission, "owner_approved")

      expect(submission.deliveries.find_by(delivery_type: "agent_approved").recipient_email).to eq("agent@example.com")
    end

    it "adds no agent delivery for the other onboarding steps" do
      described_class.for_submission(submission)
      described_class.for_owners(submission, "owner_changes_requested")
      described_class.for_owners(submission, "owner_launch_decision_required")

      expect(submission.deliveries.where(delivery_type: OnboardingDelivery::DELIVERY_TYPES.grep(/\Aagent_/))).to be_empty
    end

    it "does not add the same agent delivery twice" do
      2.times { described_class.for_owners(submission, "owner_approved") }

      expect(submission.deliveries.where(delivery_type: "agent_approved").count).to eq(1)
    end
  end

  it "adds no agent delivery when no agent is linked" do
    described_class.for_owners(submission, "owner_approved")

    expect(submission.deliveries.where(delivery_type: "agent_approved")).to be_empty
  end
end
