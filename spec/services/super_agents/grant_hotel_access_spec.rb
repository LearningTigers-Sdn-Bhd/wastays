# frozen_string_literal: true

require "rails_helper"

RSpec.describe SuperAgents::GrantHotelAccess do
  let(:hotel) { create(:hotel) }
  let!(:general_manager) { create(:role, account: hotel.account, slug: "general_manager") }
  let(:agent) { create(:user, :super_agent) }

  it "gives the agent General Manager access" do
    access = described_class.call(agent: agent, hotel: hotel)

    expect(access).to have_attributes(user: agent, hotel: hotel, role: general_manager, deactivated_at: nil)
  end

  it "reactivates access the owner removed earlier" do
    old = create(:user_hotel_access, user: agent, hotel: hotel, role: create(:role, account: hotel.account), deactivated_at: 1.day.ago)

    described_class.call(agent: agent, hotel: hotel)

    expect(old.reload).to have_attributes(role: general_manager, deactivated_at: nil)
  end
end
