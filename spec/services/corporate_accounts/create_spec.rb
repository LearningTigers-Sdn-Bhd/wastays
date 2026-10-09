require "rails_helper"

RSpec.describe CorporateAccounts::Create do
  let!(:hotel) { create(:hotel) }
  let(:attributes) { { email: " NEW@example.com ", account_name: "New Agency", name: "Agent Contact", account_type: "travel_agent" } }

  it "creates a login with encrypted temporary credentials and a direct-bill hotel link" do
    result = described_class.call(hotel: hotel, attributes: attributes)
    expect(result.success?).to be(true)
    expect(result.created).to be(true)
    expect(result.relationship).to have_attributes(relationship_type: "direct_bill", credit_currency: hotel.default_currency,
      account_type: "travel_agent", status: "active")
    user = result.user.reload
    expect(user.email).to eq("new@example.com")
    expect(user.temporary_password.length).to eq(16)
    expect(user.authenticate(user.temporary_password)).to eq(user)
    expect(user.temporary_password_hotel).to eq(hotel)
    expect(user.ciphertext_for(:temporary_password)).not_to include(user.temporary_password)
  end

  it "links any existing corporate login without changing its profile or password" do
    user = create(:user, :corporate, email: "new@example.com")
    digest = user.password_digest
    name = user.name
    account_name = user.account.name
    expect {
      result = described_class.call(hotel: hotel, attributes: attributes.merge(relationship_type: "standard"))
      expect(result.created).to be(false)
      expect(result.relationship.corporate_account).to eq(user.account)
      expect(result.relationship.relationship_type).to eq("standard")
    }.not_to change(User, :count)
    expect(user.reload).to have_attributes(name: name, password_digest: digest, temporary_password: nil)
    expect(user.account.reload.name).to eq(account_name)
  end

  it "rolls back the account and login if relationship creation fails" do
    expect {
      result = described_class.call(hotel: hotel, attributes: attributes.merge(credit_limit: -1))
      expect(result.success?).to be(false)
    }.not_to change(Account, :count)
    expect(User.find_by(email: "new@example.com")).to be_nil
  end

  it "requires a company and contact name for a new login" do
    result = described_class.call(hotel: hotel, attributes: { email: "new@example.com" })
    expect(result.success?).to be(false)
    expect(result.error).to include("Name")
  end

  it "rechecks eligibility at submission" do
    create(:user, email: "new@example.com")
    expect(described_class.call(hotel: hotel, attributes: attributes).error).to include("hotel staff")
  end

  it "uses unique slugs and keeps booking-disabled accounts free of a payment hold" do
    create(:account, name: "New Agency")
    result = described_class.call(hotel: hotel, attributes: attributes.merge(agent_payment_hold_amount: 3, agent_payment_hold_unit: "days"))
    expect(result.success?).to be(true)
    expect(result.user.account.slug).to eq("new-agency-2")
    expect(result.relationship.agent_payment_hold_hours).to be_nil
  end
end
