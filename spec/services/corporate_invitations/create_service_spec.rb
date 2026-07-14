# frozen_string_literal: true

require "rails_helper"

RSpec.describe CorporateInvitations::CreateService do
  let(:hotel_account) { create(:account) }
  let(:hotel) { create(:hotel, account: hotel_account) }
  let(:inviter) { create(:user, account: hotel_account) }
  let(:attributes) do
    {
      email: "billing@acme.test",
      relationship_type: "direct_bill",
      direct_bill_enabled: true,
      credit_limit: "5000",
      payment_terms_days: "30"
    }
  end

  it "creates a pending corporate invitation without creating access records" do
    hotel
    inviter

    expect {
      result = described_class.new(hotel: hotel, invited_by_user: inviter, attributes: attributes).call
      expect(result).to be_success
      expect(result.invitation.metadata).to include(
        "relationship_type" => "direct_bill",
        "direct_bill_enabled" => true,
        "credit_limit" => "5000.0",
        "payment_terms_days" => 30
      )
    }.to change(CorporateInvitation, :count).by(1)
      .and change(User, :count).by(0)
      .and change(HotelCorporateAccount, :count).by(0)
  end

  it "blocks an email belonging to hotel staff" do
    staff = create(:user, email: attributes[:email])

    result = described_class.new(hotel: hotel, invited_by_user: inviter, attributes: attributes).call

    expect(result).not_to be_success
    expect(result.error).to include("hotel staff")
    expect(staff).not_to be_corporate
  end

  it "refreshes an existing unaccepted invitation" do
    invitation = create(:corporate_invitation, hotel: hotel, account: hotel_account, invited_by_user: inviter, email: attributes[:email])
    old_digest = invitation.token_digest

    expect {
      described_class.new(hotel: hotel, invited_by_user: inviter, attributes: attributes).call
    }.not_to change(CorporateInvitation, :count)

    expect(invitation.reload.token_digest).not_to eq(old_digest)
    expect(invitation.relationship_type).to eq("direct_bill")
  end

  it "defaults account_type to company when not specified" do
    result = described_class.new(hotel: hotel, invited_by_user: inviter, attributes: attributes).call

    expect(result.invitation.account_type).to eq("company")
  end

  it "carries a specified account_type through to the invitation" do
    result = described_class.new(hotel: hotel, invited_by_user: inviter, attributes: attributes.merge(account_type: "airline")).call

    expect(result.invitation.account_type).to eq("airline")
  end

  it "blocks a suspended corporate account" do
    user = create(:user, :corporate, email: attributes[:email])
    user.account.update!(status: "suspended")

    result = described_class.new(hotel: hotel, invited_by_user: inviter, attributes: attributes).call

    expect(result).not_to be_success
    expect(result.error).to include("suspended")
  end
end
