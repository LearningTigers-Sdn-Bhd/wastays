# frozen_string_literal: true

require "rails_helper"

RSpec.describe SuperAgents::HotelDefaults do
  it "returns the fixed platform choices with the Enterprise plan" do
    enterprise = Plan.find_by(slug: "enterprise") || create(:plan, slug: "enterprise")

    expect(described_class.call).to eq(
      plan_id: enterprise.id, preferred_channel_manager: "undecided",
      allow_boat_information: false, hide_payout_reports: true
    )
  end
end
