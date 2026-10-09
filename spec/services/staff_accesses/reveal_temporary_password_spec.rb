# frozen_string_literal: true

require "rails_helper"

RSpec.describe StaffAccesses::RevealTemporaryPassword do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, account: hotel.account, temporary_password: "password123", temporary_password_hotel: hotel) }
  let(:access) { create(:user_hotel_access, user: user, hotel: hotel, role: create(:role, account: hotel.account)) }

  def reveal
    described_class.call(access: access, hotel: hotel)
  end

  it "reveals a working temporary password for active staff at its creating property" do
    expect(reveal.user).to eq(user)
    expect(described_class.available?(access: access, hotel: hotel)).to be(true)
  end

  it "refuses revoked access" do
    access.deactivate!
    expect(reveal.success?).to be(false)
  end

  it "refuses access from another property" do
    expect(described_class.call(access: access, hotel: create(:hotel)).success?).to be(false)
  end

  it "refuses passwords created at a sibling property" do
    user.update!(temporary_password_hotel: create(:hotel, account: hotel.account))
    expect(reveal.success?).to be(false)
  end

  it "refuses staff from another account" do
    user.update!(account: create(:account))
    expect(reveal.success?).to be(false)
  end

  it "refuses other platform roles" do
    user.update!(role: "admin")
    expect(reveal.success?).to be(false)
  end

  it "refuses a stored temporary password that no longer authenticates" do
    user.update!(password: "changed-password", password_confirmation: "changed-password")
    expect(reveal.success?).to be(false)
  end

  it "refuses credentials after a self-service password change" do
    Users::UpdateProfile.call(user: user, params: { current_password: "password123", password: "personal-password", password_confirmation: "personal-password" })
    expect(reveal.success?).to be(false)
    expect(user.reload.temporary_password).to be_nil
    expect(user.temporary_password_hotel).to be_nil
  end
end
