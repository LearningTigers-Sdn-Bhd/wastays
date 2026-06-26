# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelCorporateAccount, type: :model do
  it "requires a corporate account" do
    relationship = build(:hotel_corporate_account, corporate_account: build(:account))

    expect(relationship).not_to be_valid
    expect(relationship.errors[:corporate_account]).to include("must be a corporate account")
  end

  it "suspends and reactivates a hotel relationship independently" do
    relationship = create(:hotel_corporate_account)

    relationship.suspend!
    expect(relationship).to be_suspended
    expect(relationship.suspended_at).to be_present

    relationship.reactivate!
    expect(relationship).to be_active
    expect(relationship.suspended_at).to be_nil
  end
end
