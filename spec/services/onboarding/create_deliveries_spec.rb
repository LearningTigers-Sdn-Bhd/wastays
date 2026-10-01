# frozen_string_literal: true

require "rails_helper"

RSpec.describe Onboarding::CreateDeliveries do
  let(:hotel) { create(:hotel) }
  let(:submission) { create(:onboarding_submission, hotel:, submitted_by: create(:user, account: hotel.account)) }

  context "with a linked super agent" do
    let(:agent) { create(:user, :super_agent, email: "agent@example.com") }

    before { hotel.update!(created_by_user: agent) }

    it "adds an agent delivery on submission" do
      described_class.for_submission(submission)

      expect(submission.deliveries.find_by(delivery_type: "agent_submitted").recipient_email).to eq("agent@example.com")
    end

    it "adds the matching agent delivery for each owner step" do
      described_class::AGENT_TYPES.except("admin_submitted").each do |owner_type, agent_type|
        described_class.for_owners(submission, owner_type)

        expect(submission.deliveries.where(delivery_type: agent_type)).to exist
      end
    end

    it "does not add the same agent delivery twice" do
      2.times { described_class.for_submission(submission) }

      expect(submission.deliveries.where(delivery_type: "agent_submitted").count).to eq(1)
    end
  end

  it "adds no agent delivery when no agent is linked" do
    described_class.for_submission(submission)

    expect(submission.deliveries.where(delivery_type: described_class::AGENT_TYPES.values)).to be_empty
  end
end
