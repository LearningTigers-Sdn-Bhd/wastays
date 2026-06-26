# frozen_string_literal: true

require "rails_helper"

RSpec.describe CorporateArPaymentIntent, type: :model do
  it "requires an active relationship on creation" do
    relationship = create(:hotel_corporate_account, status: "suspended")
    intent = build(:corporate_ar_payment_intent, hotel_corporate_account: relationship, hotel: relationship.hotel, corporate_account: relationship.corporate_account)

    expect(intent).not_to be_valid
    expect(intent.errors[:hotel_corporate_account]).to include("must be active")
  end
end
