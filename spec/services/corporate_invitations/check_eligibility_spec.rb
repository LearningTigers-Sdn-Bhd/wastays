# frozen_string_literal: true

require "rails_helper"

RSpec.describe CorporateInvitations::CheckEligibility do
  let(:hotel) { create(:hotel) }

  it "allows an email that does not belong to an existing user" do
    expect(described_class.call(hotel: hotel, email: "new@company.test")).to be_success
  end

  it "rejects an email belonging to hotel staff" do
    create(:user, email: "staff@company.test")

    result = described_class.call(hotel: hotel, email: " STAFF@company.test ")

    expect(result).not_to be_success
    expect(result.error).to include("hotel staff")
  end

  it "rejects a suspended corporate account" do
    user = create(:user, :corporate, email: "billing@company.test")
    user.account.update!(status: "suspended")

    result = described_class.call(hotel: hotel, email: user.email)

    expect(result).not_to be_success
    expect(result.error).to include("suspended")
  end

  it "rejects a corporate account already linked to the hotel" do
    user = create(:user, :corporate, email: "linked@company.test")
    create(:hotel_corporate_account, hotel: hotel, corporate_account: user.account)

    result = described_class.call(hotel: hotel, email: user.email)

    expect(result).not_to be_success
    expect(result.error).to include("already linked")
  end
end
