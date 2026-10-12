require "rails_helper"

RSpec.describe CorporateAccounts::Lookup do
  let(:hotel) { create(:hotel) }

  it "normalizes an existing corporate login without creating a link" do
    user = create(:user, :corporate)
    expect {
      result = described_class.call(hotel: hotel, email: " #{user.email.upcase} ")
      expect(result.success?).to be(true)
      expect(result.user).to eq(user)
    }.not_to change(HotelCorporateAccount, :count)
  end

  it "accepts a new email without creating a user" do
    expect {
      expect(described_class.call(hotel: hotel, email: "new@example.com").user).to be_nil
    }.not_to change(User, :count)
  end

  it "rejects invalid emails and hotel staff" do
    expect(described_class.call(hotel: hotel, email: "invalid").success?).to be(false)
    staff = create(:user)
    expect(described_class.call(hotel: hotel, email: staff.email).error).to include("hotel staff")
  end

  it "rejects a suspended account or hotel relationship" do
    user = create(:user, :corporate)
    user.account.update!(status: "suspended")
    expect(described_class.call(hotel: hotel, email: user.email).error).to include("suspended")
    user.account.update!(status: "active")
    create(:hotel_corporate_account, corporate_account: user.account, hotel: hotel, status: "suspended")
    expect(described_class.call(hotel: hotel, email: user.email).error).to include("Reactivate")
  end

  it "rejects an already linked account" do
    user = create(:user, :corporate)
    create(:hotel_corporate_account, corporate_account: user.account, hotel: hotel)
    expect(described_class.call(hotel: hotel, email: user.email).error).to include("already linked")
  end
end
