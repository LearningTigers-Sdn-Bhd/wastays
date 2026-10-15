# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Hotels::UpdateSuperAgent do
  let(:hotel) { create(:hotel) }
  let!(:general_manager) { create(:role, account: hotel.account, slug: "general_manager") }
  let(:agent) { create(:user, :super_agent) }
  let(:other_agent) { create(:user, :super_agent) }

  it "links the agent and gives them access" do
    described_class.call(hotel: hotel, agent: agent)

    expect(hotel.reload.created_by_user).to eq(agent)
    expect(agent.user_hotel_accesses.find_by(hotel: hotel).role).to eq(general_manager)
  end

  it "moves the hotel to another agent and removes the old access" do
    described_class.call(hotel: hotel, agent: agent)
    described_class.call(hotel: hotel, agent: other_agent)

    expect(hotel.reload.created_by_user).to eq(other_agent)
    expect(agent.user_hotel_accesses.where(hotel: hotel)).to be_empty
  end

  it "unlinks the agent" do
    described_class.call(hotel: hotel, agent: agent)
    described_class.call(hotel: hotel, agent: nil)

    expect(hotel.reload.created_by_user).to be_nil
    expect(agent.user_hotel_accesses.where(hotel: hotel)).to be_empty
  end

  it "keeps a superadmin creator's access untouched" do
    superadmin = create(:user, :superadmin)
    hotel.update!(created_by_user: superadmin)
    access = create(:user_hotel_access, user: superadmin, hotel: hotel, role: general_manager)

    described_class.call(hotel: hotel, agent: agent)

    expect(UserHotelAccess.exists?(access.id)).to be(true)
  end
end
