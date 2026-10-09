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

  context "with a corporate temporary password" do
    let(:hotel) { create(:hotel) }
    let(:user) { create(:user, :corporate, password: "first-password-123", temporary_password: "first-password-123", temporary_password_hotel: hotel) }

    it "clears the temporary credentials on a successful password change" do
      expect(described_class.call(user: user, params: {
        current_password: "first-password-123", password: "personal-password", password_confirmation: "personal-password"
      })).to be(true)
      expect(user.reload).to have_attributes(temporary_password: nil, temporary_password_hotel_id: nil)
      expect(user.authenticate("personal-password")).to eq(user)
    end

    it "retains the credentials when authentication or confirmation fails" do
      [ { current_password: "wrong", password_confirmation: "personal-password" },
        { current_password: "first-password-123", password_confirmation: "mismatch" } ].each do |params|
        expect(described_class.call(user: user, params: params.merge(password: "personal-password"))).to be(false)
        expect(user.reload.temporary_password).to eq("first-password-123")
      end
    end

    it "retains credentials when only profile details change" do
      expect(described_class.call(user: user, params: { name: "Updated Contact" })).to be(true)
      expect(user.reload.temporary_password).to eq("first-password-123")
    end
  end
end
