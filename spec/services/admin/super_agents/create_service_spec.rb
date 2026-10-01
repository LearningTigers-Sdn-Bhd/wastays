# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::SuperAgents::CreateService do
  let(:account) { create(:account) }

  it "creates a super agent with a password that signs in" do
    result = described_class.new(account: account, params: { name: "Aina", email: "aina@example.com" }).call

    expect(result.success?).to be(true)
    expect(result.agent).to have_attributes(role: "super_agent", account: account)
    expect(result.agent.authenticate(result.password)).to eq(result.agent)
  end

  it "uses a typed password" do
    result = described_class.new(account: account, params: { name: "Aina", email: "aina@example.com", password: "typed-password-123" }).call

    expect(result.password).to eq("typed-password-123")
    expect(result.agent.authenticate("typed-password-123")).to eq(result.agent)
  end

  it "rejects a typed password that is too short" do
    result = described_class.new(account: account, params: { name: "Aina", email: "aina@example.com", password: "short" }).call

    expect(result.success?).to be(false)
    expect(result.agent).not_to be_persisted
    expect(result.agent.errors[:password]).to include("must be at least 8 characters")
  end

  it "returns the errors when the email is taken" do
    create(:user, email: "aina@example.com")

    result = described_class.new(account: account, params: { name: "Aina", email: "aina@example.com" }).call

    expect(result.success?).to be(false)
    expect(result.agent.errors[:email]).to be_present
  end
end
