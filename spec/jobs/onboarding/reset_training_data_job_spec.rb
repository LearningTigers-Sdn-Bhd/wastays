# frozen_string_literal: true

require "rails_helper"

RSpec.describe Onboarding::ResetTrainingDataJob, type: :job do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account:) }
  let(:actor) { create(:user, account:) }

  it "delegates reset execution using persisted identifiers" do
    allow(Onboarding::ResetOperationalData).to receive(:call)

    described_class.perform_now(hotel.id, actor.id)

    expect(Onboarding::ResetOperationalData).to have_received(:call).with(hotel:, actor:)
  end

  it "quietly discards work for a deleted hotel" do
    hotel_id = hotel.id
    hotel.destroy!
    allow(Onboarding::ResetOperationalData).to receive(:call)

    expect { described_class.perform_now(hotel_id, actor.id) }.not_to raise_error
    expect(Onboarding::ResetOperationalData).not_to have_received(:call)
  end
end
