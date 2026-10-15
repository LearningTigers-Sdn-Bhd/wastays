require "rails_helper"

RSpec.describe Admin::Hotels::UpdateAccount, type: :service do
  let(:account) { create(:account, name: "Old account") }
  let(:hotel) { create(:hotel, account:) }
  let(:owner) { create(:user, :admin, account:, name: "Old owner", email: "old-owner@example.com") }

  it "updates the account and owner and expires reset links when the email changes" do
    reset = OwnerPasswordReset.create!(user: owner, token_digest: Digest::SHA256.hexdigest("old-token"), expires_at: 10.minutes.from_now)

    expect(described_class.call(hotel:, owner:, account_name: "New account", owner_name: "New owner", owner_email: "new-owner@example.com")).to be(true)

    expect(account.reload.name).to eq("New account")
    expect(owner.reload).to have_attributes(name: "New owner", email: "new-owner@example.com")
    expect(OwnerPasswordReset.exists?(reset.id)).to be(false)
  end

  it "keeps reset links when the owner email does not change" do
    reset = OwnerPasswordReset.create!(user: owner, token_digest: Digest::SHA256.hexdigest("old-token"), expires_at: 10.minutes.from_now)

    described_class.call(hotel:, owner:, account_name: "New account", owner_name: "New owner", owner_email: owner.email)

    expect(OwnerPasswordReset.exists?(reset.id)).to be(true)
  end

  it "rolls back the account update when owner details are invalid" do
    expect {
      described_class.call(hotel:, owner:, account_name: "New account", owner_name: "New owner", owner_email: "invalid")
    }.to raise_error(ActiveRecord::RecordInvalid)

    expect(account.reload.name).to eq("Old account")
    expect(owner.reload).to have_attributes(name: "Old owner", email: "old-owner@example.com")
  end
end
