# frozen_string_literal: true

require "rails_helper"

RSpec.describe StaffAccesses::DestroyService do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account) }
  let(:manage_account) do
    Permission.find_or_create_by!(slug: UserHotelAccess::ACCOUNT_MANAGEMENT_PERMISSION) do |record|
      record.name = "Manage Account"
    end
  end
  let(:manager_role) { create(:role, account: account, permissions: [ manage_account ]) }
  let(:plain_role) { create(:role, account: account) }
  let(:current_user) { create(:user, account: account) }

  def access_for(user, role: plain_role)
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
  end

  it "deletes the access row and returns it" do
    access = access_for(create(:user, account: account))

    result = described_class.new(access: access, current_user: current_user).call

    expect(result.success?).to be(true)
    expect(result.access).to eq(access)
    expect(UserHotelAccess.exists?(access.id)).to be(false)
  end

  it "leaves the user record alone" do
    user = create(:user, account: account)
    access = access_for(user)

    described_class.new(access: access, current_user: current_user).call

    expect(User.exists?(user.id)).to be(true)
  end

  it "refuses to delete the current user's own access" do
    access = access_for(current_user)

    result = described_class.new(access: access, current_user: current_user).call

    expect(result.success?).to be(false)
    expect(result.error).to eq("You cannot delete your own access.")
    expect(UserHotelAccess.exists?(access.id)).to be(true)
  end

  it "refuses to delete the sole account manager" do
    manager = create(:user, account: account, name: "Only Manager")
    access = access_for(manager, role: manager_role)

    result = described_class.new(access: access, current_user: current_user).call

    expect(result.success?).to be(false)
    expect(result.error).to eq(
      "Only Manager is the only person who can manage this account. Give someone else account management first."
    )
    expect(UserHotelAccess.exists?(access.id)).to be(true)
  end

  it "deletes an account manager once another active manager remains" do
    access = access_for(create(:user, account: account), role: manager_role)
    access_for(create(:user, account: account), role: manager_role)

    result = described_class.new(access: access, current_user: current_user).call

    expect(result.success?).to be(true)
    expect(UserHotelAccess.exists?(access.id)).to be(false)
  end

  # A deactivated manager is not holding the account open, so nothing is lost by
  # removing the row.
  it "deletes a deactivated sole account manager" do
    access = access_for(create(:user, account: account), role: manager_role)
    access.deactivate!

    result = described_class.new(access: access, current_user: current_user).call

    expect(result.success?).to be(true)
    expect(UserHotelAccess.exists?(access.id)).to be(false)
  end

  # The lockout guard is per property; a manager at another hotel cannot restore
  # access here.
  it "refuses when the only other manager belongs to a different property" do
    other_hotel = create(:hotel, account: account)
    access = access_for(create(:user, account: account), role: manager_role)
    create(:user_hotel_access, user: create(:user, account: account), hotel: other_hotel, role: manager_role)

    result = described_class.new(access: access, current_user: current_user).call

    expect(result.success?).to be(false)
    expect(UserHotelAccess.exists?(access.id)).to be(true)
  end
end
