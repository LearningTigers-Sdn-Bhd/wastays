require "rails_helper"

RSpec.describe CorporateAccounts::RevealTemporaryPassword do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, :corporate, password: "temporary-password", temporary_password: "temporary-password", temporary_password_hotel: hotel) }
  let(:relationship) { create(:hotel_corporate_account, hotel: hotel, corporate_account: user.account) }

  it "reveals a temporary password only to its creating hotel" do
    expect(described_class.call(relationship: relationship, hotel: hotel).user).to eq(user)
    other = create(:hotel_corporate_account, corporate_account: user.account)
    expect(described_class.call(relationship: other, hotel: other.hotel).success?).to be(false)
    expect(described_class.call(relationship: relationship, hotel: other.hotel).success?).to be(false)
  end

  it "does not reveal a cleared or stale password" do
    user.update!(password: "personal-password")
    expect(described_class.call(relationship: relationship, hotel: hotel).success?).to be(false)
    user.update!(temporary_password: nil, temporary_password_hotel: nil)
    expect(described_class.call(relationship: relationship, hotel: hotel).success?).to be(false)
  end
end
