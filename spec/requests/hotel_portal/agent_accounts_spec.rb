require 'rails_helper'

RSpec.describe "HotelPortal::AgentAccounts", type: :request do
  let!(:account) { create(:account) }
  let!(:hotel) { create(:hotel, account: account) }
  let!(:user) { create(:user, account: account, role: 'admin', password: 'password', password_confirmation: 'password') }
  let!(:agent_account) { create(:agent_account, hotel: hotel) }

  before do
    role = Role.create!(name: "Admin", account: account)
    [ :view_agent_accounts, :manage_agent_accounts ].each do |slug|
      permission = Permission.find_or_create_by!(slug: slug) { |p| p.name = slug.to_s.humanize }
      role.permissions << permission
    end
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    user.roles << role

    # Comprehensive mocking to bypass all filters/middleware
    [ ApplicationController, HotelPortal::BaseController ].each do |klass|
      allow_any_instance_of(klass).to receive(:current_user).and_return(user)
      allow_any_instance_of(klass).to receive(:logged_in?).and_return(true)
      allow_any_instance_of(klass).to receive(:authenticate_user!).and_return(true)
      allow_any_instance_of(klass).to receive(:ensure_hotel_access!).and_return(true)
      allow_any_instance_of(klass).to receive(:current_hotel).and_return(hotel)
    end
  end

  describe "GET /index" do
    it "returns http success" do
      get hotel_portal_agent_accounts_path(hotel_id: hotel.id)
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /new" do
    it "returns http success" do
      get new_hotel_portal_agent_account_path(hotel_id: hotel.id)
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /create" do
    it "creates a new agent account" do
      expect {
        post hotel_portal_agent_accounts_path(hotel_id: hotel.id), params: {
          agent_account: { name: "New Agent", account_type: "company" }
        }
      }.to change(AgentAccount, :count).by(1)
      expect(response).to redirect_to(hotel_portal_agent_accounts_path)
    end
  end

  describe "GET /edit" do
    it "returns http success" do
      get edit_hotel_portal_agent_account_path(agent_account, hotel_id: hotel.id)
      expect(response).to have_http_status(:success)
    end
  end

  describe "PATCH /update" do
    it "updates the agent account" do
      patch hotel_portal_agent_account_path(agent_account, hotel_id: hotel.id), params: {
        agent_account: { name: "Updated Name" }
      }
      expect(agent_account.reload.name).to eq("Updated Name")
      expect(response).to redirect_to(hotel_portal_agent_accounts_path)
    end
  end

  describe "DELETE /destroy" do
    it "destroys the agent account" do
      expect {
        delete hotel_portal_agent_account_path(agent_account, hotel_id: hotel.id)
      }.to change(AgentAccount, :count).by(-1)
      expect(response).to redirect_to(hotel_portal_agent_accounts_path)
    end
  end
end
