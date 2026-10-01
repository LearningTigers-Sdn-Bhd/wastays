# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::SuperAgents", type: :request do
  let(:token) { SecureRandom.hex(6) }
  let(:admin_account) { create(:account, name: "Admin #{token}") }
  let(:superadmin) { create(:user, :superadmin, account: admin_account) }

  before { sign_in_as(superadmin) }

  describe "GET /admin/super-agents" do
    it "lists the super agents" do
      create(:user, :super_agent, account: admin_account, name: "Aina #{token}")

      get admin_super_agents_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Aina #{token}")
    end
  end

  describe "POST /admin/super-agents" do
    it "creates a super agent and shows the password once" do
      expect {
        post admin_super_agents_path, params: { user: { name: "Aina", email: "aina-#{token}@example.com" } }
      }.to change(User.where(role: "super_agent"), :count).by(1)

      agent = User.find_by(email: "aina-#{token}@example.com")
      expect(agent.authenticate(flash[:agent_credentials]["password"])).to eq(agent)

      follow_redirect!
      expect(response.body).to include("Agent sign-in details")
    end

    it "uses the password the superadmin typed" do
      post admin_super_agents_path, params: { user: { name: "Aina", email: "aina-#{token}@example.com", password: "typed-password-123" } }

      agent = User.find_by(email: "aina-#{token}@example.com")
      expect(agent.authenticate("typed-password-123")).to eq(agent)
      expect(flash[:agent_credentials]["password"]).to eq("typed-password-123")
    end

    it "rejects a typed password shorter than 8 characters" do
      expect {
        post admin_super_agents_path, params: { user: { name: "Aina", email: "aina-#{token}@example.com", password: "short" } }
      }.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Password must be at least 8 characters")
    end

    it "re-renders the form when the email is missing" do
      post admin_super_agents_path, params: { user: { name: "Aina", email: "" } }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /admin/super-agents/:id" do
    it "removes the agent and keeps their hotels" do
      agent = create(:user, :super_agent, account: admin_account)
      hotel = create(:hotel, created_by_user: agent)

      delete admin_super_agent_path(agent)

      expect(User.exists?(agent.id)).to be(false)
      expect(hotel.reload.created_by_user_id).to be_nil
    end
  end
end
