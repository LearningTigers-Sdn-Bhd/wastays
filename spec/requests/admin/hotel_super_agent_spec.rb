# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin hotel Super agent tab", type: :request do
  let(:admin_account) { create(:account) }
  let(:superadmin) { create(:user, :superadmin, account: admin_account) }
  let(:hotel) { create(:hotel) }
  let!(:agent) { create(:user, :super_agent, account: admin_account, name: "Aina Agent") }

  before do
    create(:role, account: hotel.account, slug: "general_manager")
    sign_in_as(superadmin)
  end

  it "lists the super agents to pick from" do
    get admin_hotel_path(hotel, tab: "super_agent")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Aina Agent · #{agent.agent_code}")
  end

  it "links the hotel to the picked agent" do
    patch update_super_agent_admin_hotel_path(hotel), params: { super_agent: { id: agent.id } }

    expect(response).to redirect_to(admin_hotel_path(hotel, tab: "super_agent"))
    expect(hotel.reload.created_by_user).to eq(agent)
    expect(agent.hotels).to include(hotel)
  end

  it "unlinks the agent" do
    hotel.update!(created_by_user: agent)

    patch update_super_agent_admin_hotel_path(hotel), params: { super_agent: { id: "" } }

    expect(hotel.reload.created_by_user).to be_nil
  end
end
