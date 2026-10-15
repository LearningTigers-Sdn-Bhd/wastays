require "rails_helper"

RSpec.describe Admin::Hotels::ChangeOwnerPassword, type: :service do
  let(:user) { create(:user) }

  it "changes the password, expires reset links, and invalidates existing sessions" do
    reset = OwnerPasswordReset.create!(user:, token_digest: Digest::SHA256.hexdigest("old-token"), expires_at: 10.minutes.from_now)
    old_version = user.auth_version

    expect(described_class.call(user:, password: "NewPassword123!", password_confirmation: "NewPassword123!")).to be(true)

    expect(user.reload.authenticate("NewPassword123!")).to eq(user)
    expect(user.auth_version).to eq(old_version + 1)
    expect(OwnerPasswordReset.exists?(reset.id)).to be(false)
  end

  it "preserves the password and reset links when the password is too short" do
    reset = OwnerPasswordReset.create!(user:, token_digest: Digest::SHA256.hexdigest("old-token"), expires_at: 10.minutes.from_now)
    old_version = user.auth_version

    expect {
      described_class.call(user:, password: "short", password_confirmation: "short")
    }.to raise_error(ActiveRecord::RecordInvalid, /at least 12 characters/)

    expect(user.reload.authenticate("password123")).to eq(user)
    expect(user.auth_version).to eq(old_version)
    expect(OwnerPasswordReset.exists?(reset.id)).to be(true)
  end

  it "rejects a mismatched confirmation without changing the password" do
    expect {
      described_class.call(user:, password: "NewPassword123!", password_confirmation: "DifferentPassword123!")
    }.to raise_error(ActiveRecord::RecordInvalid)

    expect(user.reload.authenticate("password123")).to eq(user)
  end
end
