# frozen_string_literal: true

require "rails_helper"

RSpec.describe Users::UpdateProfile do
  let(:user) { create(:user, password: "first-password-123") }

  it "saves details without a current password" do
    expect(described_class.call(user: user, params: { name: "New Name" })).to be(true)
    expect(user.reload.name).to eq("New Name")
  end

  it "changes the password when the current password is correct" do
    saved = described_class.call(user: user, params: {
      current_password: "first-password-123", password: "new-password-456", password_confirmation: "new-password-456"
    })

    expect(saved).to be(true)
    expect(user.reload.authenticate("new-password-456")).to eq(user)
  end

  it "keeps the password when the current password is wrong" do
    saved = described_class.call(user: user, params: {
      current_password: "wrong", password: "new-password-456", password_confirmation: "new-password-456"
    })

    expect(saved).to be(false)
    expect(user.errors.full_messages).to include("Current password is not correct")
    expect(user.reload.authenticate("first-password-123")).to eq(user)
  end

  it "keeps the password when the current password is missing" do
    saved = described_class.call(user: user, params: { password: "new-password-456", password_confirmation: "new-password-456" })

    expect(saved).to be(false)
    expect(user.reload.authenticate("first-password-123")).to eq(user)
  end
end
