# frozen_string_literal: true

require "rails_helper"

RSpec.describe StaffAccesses::LookupService do
  let(:hotel) { create(:hotel) }

  def lookup(email)
    described_class.new(hotel: hotel, email: email).call
  end

  it "looks up a new email without creating a user, access, or invitation" do
    hotel
    counts = [ User.count, UserHotelAccess.count, StaffInvitation.count ]
    result = lookup("  New.Staff@Example.COM  ")

    expect(result.success?).to be(true)
    expect(result.user).to be_nil
    expect(result.outstanding_invitation).to be(false)
    expect([ User.count, UserHotelAccess.count, StaffInvitation.count ]).to eq(counts)
  end

  it "normalizes the email and finds eligible staff from a sibling property" do
    user = create(:user, account: hotel.account)
    sibling = create(:hotel, account: hotel.account)
    create(:user_hotel_access, user: user, hotel: sibling, role: create(:role, account: hotel.account))

    result = lookup("  #{user.email.upcase}  ")

    expect(result.success?).to be(true)
    expect(result.user).to eq(user)
  end

  [ "", "not-an-email" ].each do |email|
    it "rejects invalid email #{email.inspect}" do
      expect(lookup(email).error).to eq("Enter a valid login email.")
    end
  end

  [ nil, 1.day.ago ].each do |deactivated_at|
    it "rejects #{deactivated_at ? 'revoked' : 'active'} access without exposing a login" do
      user = create(:user, account: hotel.account)
      create(:user_hotel_access, user: user, hotel: hotel, role: create(:role, account: hotel.account), deactivated_at: deactivated_at)

      result = lookup(user.email)

      expect(result.success?).to be(false)
      expect(result.user).to be_nil
      expect(result.error).to include(deactivated_at ? "Restore access through their existing staff row" : "already has access")
    end
  end

  %w[corporate super_agent superadmin admin salesperson].each do |role|
    it "rejects #{role} logins without exposing their identity" do
      user = create(:user, role.to_sym)

      result = lookup(user.email)

      expect(result.success?).to be(false)
      expect(result.user).to be_nil
      expect(result.error).to eq("This login cannot be added as staff. Use a separate staff email.")
    end
  end

  it "rejects staff from another account without exposing their identity" do
    user = create(:user)

    result = lookup(user.email)

    expect(result.success?).to be(false)
    expect(result.user).to be_nil
  end

  it "reports outstanding expired or unsent invitations but excludes accepted history" do
    invitation = create(:staff_invitation, :held, hotel: hotel, account: hotel.account, expires_at: 1.day.ago)
    expect(lookup(invitation.email).outstanding_invitation).to be(true)

    invitation.update!(accepted_at: Time.current)
    expect(lookup(invitation.email).outstanding_invitation).to be(false)
  end
end
