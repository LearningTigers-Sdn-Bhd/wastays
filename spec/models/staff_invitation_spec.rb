# frozen_string_literal: true

require "rails_helper"

RSpec.describe StaffInvitation, type: :model do
  describe ".find_by_token" do
    it "matches the digest without storing the raw token" do
      token = "raw-token"
      invitation = create(:staff_invitation, token_digest: described_class.digest(token))

      expect(described_class.find_by_token(token)).to eq(invitation)
      expect(invitation.token_digest).not_to eq(token)
    end
  end

  describe "validations" do
    it "requires the role to belong to the same account" do
      invitation = build(:staff_invitation, role: create(:role))

      expect(invitation).not_to be_valid
      expect(invitation.errors[:role]).to include("must belong to the invitation account")
    end
  end

  describe "#pending?" do
    it "is false after expiry" do
      invitation = build(:staff_invitation, expires_at: 1.minute.ago)

      expect(invitation).not_to be_pending
    end
  end

  describe "#accept!" do
    it "creates hotel access and marks the invitation accepted" do
      invitation = create(:staff_invitation)
      user = create(:user, email: invitation.email, account: invitation.account)

      expect { invitation.accept!(user) }.to change(UserHotelAccess, :count).by(1)

      expect(invitation).to be_accepted
      expect(user.user_hotel_accesses.last.role).to eq(invitation.role)
    end
  end
end
