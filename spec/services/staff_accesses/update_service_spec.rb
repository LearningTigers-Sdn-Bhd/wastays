# frozen_string_literal: true

require "rails_helper"

RSpec.describe StaffAccesses::UpdateService do
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
  let(:access) { create(:user_hotel_access, user: create(:user, account: account), hotel: hotel, role: plain_role) }

  def manager_access(name: "Only Manager")
    create(:user_hotel_access, user: create(:user, account: account, name: name), hotel: hotel, role: manager_role)
  end

  it "assigns the given role" do
    result = described_class.new(access: access, current_user: current_user, role: manager_role).call

    expect(result.success?).to be(true)
    expect(access.reload.role).to eq(manager_role)
  end

  it "deactivates when active is false" do
    result = described_class.new(access: access, current_user: current_user, active: false).call

    expect(result.success?).to be(true)
    expect(access.reload).not_to be_active
  end

  it "reactivates when active is true" do
    access.deactivate!

    result = described_class.new(access: access, current_user: current_user, active: true).call

    expect(result.success?).to be(true)
    expect(access.reload).to be_active
  end

  it "applies a role change and a status change together" do
    result = described_class.new(access: access, current_user: current_user, role: manager_role, active: false).call

    expect(result.success?).to be(true)
    expect(access.reload.role).to eq(manager_role)
    expect(access).not_to be_active
  end

  # nil means "leave it alone", so the listing row's status toggle never clears
  # the role the edit sheet set.
  it "leaves the role untouched when role is nil" do
    result = described_class.new(access: access, current_user: current_user, active: false).call

    expect(result.success?).to be(true)
    expect(access.reload.role).to eq(plain_role)
  end

  it "leaves the status untouched when active is nil" do
    access.deactivate!

    result = described_class.new(access: access, current_user: current_user, role: manager_role).call

    expect(result.success?).to be(true)
    expect(access.reload).not_to be_active
  end

  it "refuses to change the current user's own access" do
    own = create(:user_hotel_access, user: current_user, hotel: hotel, role: plain_role)

    result = described_class.new(access: own, current_user: current_user, active: false).call

    expect(result.success?).to be(false)
    expect(result.error).to eq("You cannot change your own access.")
    expect(own.reload).to be_active
  end

  it "refuses to revoke the sole account manager" do
    sole = manager_access

    result = described_class.new(access: sole, current_user: current_user, active: false).call

    expect(result.success?).to be(false)
    expect(result.error).to eq(
      "Only Manager is the only person who can manage this account. Give someone else account management first."
    )
    expect(sole.reload).to be_active
  end

  # Demoting locks the property out just as surely as revoking, so it is refused
  # on the same grounds.
  it "refuses to demote the sole account manager to a role without account management" do
    sole = manager_access

    result = described_class.new(access: sole, current_user: current_user, role: plain_role).call

    expect(result.success?).to be(false)
    expect(sole.reload.role).to eq(manager_role)
  end

  it "allows the sole account manager to keep a role that still manages the account" do
    sole = manager_access
    other_manager_role = create(:role, account: account, permissions: [ manage_account ])

    result = described_class.new(access: sole, current_user: current_user, role: other_manager_role).call

    expect(result.success?).to be(true)
    expect(sole.reload.role).to eq(other_manager_role)
  end

  it "allows revoking an account manager once another active manager remains" do
    sole = manager_access
    manager_access(name: "Second Manager")

    result = described_class.new(access: sole, current_user: current_user, active: false).call

    expect(result.success?).to be(true)
    expect(sole.reload).not_to be_active
  end

  it "returns the validation message when the record fails to save" do
    allow(access).to receive(:save).and_return(false)
    access.errors.add(:base, "Role is not assignable")

    result = described_class.new(access: access, current_user: current_user, role: manager_role).call

    expect(result.success?).to be(false)
    expect(result.error).to eq("Role is not assignable")
    expect(result.access).to eq(access)
  end
end
