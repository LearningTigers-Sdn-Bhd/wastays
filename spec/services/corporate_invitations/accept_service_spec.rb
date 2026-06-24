# frozen_string_literal: true

require "rails_helper"

RSpec.describe CorporateInvitations::AcceptService do
  let(:invitation) do
    create(
      :corporate_invitation,
      email: "billing@acme.test",
      relationship_type: "direct_bill",
      direct_bill_enabled: true,
      credit_limit: "5000",
      payment_terms_days: "30"
    )
  end
  let(:user_attributes) do
    {
      account_name: "Acme Sdn Bhd",
      name: "Amina Lee",
      password: "password123",
      password_confirmation: "password123"
    }
  end

  it "atomically creates a corporate account, user, and active hotel relationship" do
    invitation

    expect {
      result = described_class.new(invitation: invitation, user_attributes: user_attributes).call
      expect(result).to be_success
      expect(result.user).to be_corporate
      expect(result.relationship).to be_active
    }.to change(Account.corporate, :count).by(1)
      .and change(User, :count).by(1)
      .and change(HotelCorporateAccount, :count).by(1)

    expect(invitation.reload).to be_accepted
    user = User.find_by!(email: invitation.email)
    expect(user.account).to have_attributes(name: "Acme Sdn Bhd")
    expect(HotelCorporateAccount.find_by!(corporate_account: user.account)).to have_attributes(
      relationship_type: "direct_bill",
      direct_bill_enabled: true,
      credit_limit: 5000.to_d,
      payment_terms_days: 30
    )
    expect(UserHotelAccess.where(user: user)).to be_empty
  end

  it "links an existing corporate user without changing the password" do
    user = create(:user, :corporate, email: invitation.email, password: "oldpassword")
    original_account_name = user.account.name

    expect {
      result = described_class.new(
        invitation: invitation,
        user_attributes: user_attributes.merge(account_name: "Ignored Name"),
        accepting_user: user
      ).call
      expect(result).to be_success
    }.to change(HotelCorporateAccount, :count).by(1)
      .and change(User, :count).by(0)
      .and change(Account, :count).by(0)

    expect(user.reload.authenticate("oldpassword")).to be_truthy
    expect(user.account.reload.name).to eq(original_account_name)
  end

  it "requires existing corporate users to be logged in before linking" do
    create(:user, :corporate, email: invitation.email)

    result = described_class.new(invitation: invitation).call

    expect(result).not_to be_success
    expect(result.error).to include("Log in as")
    expect(HotelCorporateAccount.where(hotel: invitation.hotel)).to be_empty
  end

  it "requires a new recipient to choose a corporate account name" do
    result = described_class.new(
      invitation: invitation,
      user_attributes: user_attributes.except(:account_name)
    ).call

    expect(result).not_to be_success
    expect(result.error).to include("Name")
  end

  it "rejects expired invitations" do
    invitation.update!(expires_at: 1.minute.ago)

    result = described_class.new(invitation: invitation, user_attributes: user_attributes).call

    expect(result).not_to be_success
    expect(result.error).to include("expired")
  end

  it "rejects an existing suspended corporate account" do
    user = create(:user, :corporate, email: invitation.email)
    user.account.update!(status: "suspended")

    result = described_class.new(invitation: invitation).call

    expect(result).not_to be_success
    expect(result.error).to include("suspended")
  end
end
