require "rails_helper"

RSpec.describe CorporateAccounts::Update do
  let(:user) { create(:user, :corporate) }
  let(:relationship) { create(:hotel_corporate_account, corporate_account: user.account) }

  it "saves shared profile and hotel details together without changing the password" do
    other = create(:hotel_corporate_account, corporate_account: user.account)
    digest = user.password_digest
    result = described_class.call(relationship: relationship,
      account_attributes: { name: "Shared Agency" }, user_attributes: { name: "Contact", email: "new@example.com", password: "ignored" },
      relationship_attributes: { contact_phone: "123", market: "local" })
    expect(result.success?).to be(true)
    expect(other.corporate_account.reload.name).to eq("Shared Agency")
    expect(user.reload).to have_attributes(name: "Contact", email: "new@example.com", password_digest: digest)
    expect(relationship.reload.contact_phone).to eq("123")
    expect(other.reload.contact_phone).to be_nil
  end

  it "rolls back all records for an email collision and retains typed values" do
    taken = create(:user)
    original_name = user.account.name
    original_email = user.email
    result = described_class.call(relationship: relationship, account_attributes: { name: "Typed Agency" },
      user_attributes: { email: taken.email }, relationship_attributes: { contact_phone: "123" })
    expect(result.success?).to be(false)
    expect(result.account.name).to eq("Typed Agency")
    expect(result.user.errors[:email]).to be_present
    expect(user.reload.email).to eq(original_email)
    expect(user.account.reload.name).to eq(original_name)
    expect(relationship.reload.contact_phone).to be_nil
  end

  it "rolls back profile edits when hotel billing validation fails" do
    original_name = user.account.name
    result = described_class.call(relationship: relationship, account_attributes: { name: "Changed" },
      relationship_attributes: { credit_limit: -1 })
    expect(result.success?).to be(false)
    expect(user.account.reload.name).to eq(original_name)
  end

  it "edits an unclaimed account without creating a login" do
    unclaimed = create(:hotel_corporate_account)
    expect {
      result = described_class.call(relationship: unclaimed, account_attributes: { name: "Imported Agency" },
        user_attributes: { name: "Ignored", email: "ignored@example.com" }, relationship_attributes: { market: "local" })
      expect(result.success?).to be(true)
      expect(result.user).to be_nil
    }.not_to change(User, :count)
    expect(unclaimed.corporate_account.reload.name).to eq("Imported Agency")
  end
end
