# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AgentPortal::Profiles", type: :request do
  let(:agent) { create(:user, :super_agent, password: "first-password-123") }

  before { sign_in_as(agent) }

  it "shows the agent profile" do
    get edit_agent_profile_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Change password")
  end

  it "changes the password" do
    patch agent_profile_path, params: { user: { name: agent.name, current_password: "first-password-123", password: "new-password-456", password_confirmation: "new-password-456" } }

    expect(response).to redirect_to(edit_agent_profile_path)
    expect(agent.reload.authenticate("new-password-456")).to eq(agent)
  end

  it "keeps the password when the fields are empty" do
    patch agent_profile_path, params: { user: { name: "New Name", password: "", password_confirmation: "" } }

    expect(agent.reload).to have_attributes(name: "New Name")
    expect(agent.authenticate("first-password-123")).to eq(agent)
  end

  it "rejects a confirmation that does not match" do
    patch agent_profile_path, params: { user: { name: agent.name, current_password: "first-password-123", password: "new-password-456", password_confirmation: "other" } }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "ignores an email change" do
    original = agent.email

    patch agent_profile_path, params: { user: { name: agent.name, email: "changed@example.com" } }

    expect(agent.reload.email).to eq(original)
  end
end

RSpec.describe "AgentPortal::Profiles current password", type: :request do
  let(:agent) { create(:user, :super_agent, password: "first-password-123") }

  before { sign_in_as(agent) }

  it "rejects a wrong current password" do
    patch agent_profile_path, params: { user: { current_password: "wrong", password: "new-password-456", password_confirmation: "new-password-456" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Current password is not correct")
    expect(agent.reload.authenticate("first-password-123")).to eq(agent)
  end
end
