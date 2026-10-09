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
    it "rejects a normalized partner email" do
      partner = create(:user, :super_agent)
      invitation = build(:staff_invitation, email: "  #{partner.email.upcase}  ")

      expect(invitation).not_to be_valid
      expect(invitation.errors[:base]).to include(described_class::PARTNER_INVITATION_ERROR)
    end

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
    [ nil, 1.day.ago ].each do |deactivated_at|
      it "preserves #{deactivated_at ? 'revoked' : 'active'} partner access when an old invitation is accepted" do
        invitation = create(:staff_invitation)
        partner = create(:user, :super_agent, email: invitation.email)
        role = create(:role, account: invitation.account)
        access = create(:user_hotel_access, user: partner, hotel: invitation.hotel, role: role, deactivated_at: deactivated_at)
        attributes = access.attributes

        expect { invitation.accept!(partner) }.to raise_error(ActiveRecord::RecordInvalid, /cannot be invited as hotel staff/)

        expect(access.reload.attributes).to eq(attributes)
        expect(invitation.reload).not_to be_accepted
      end
    end

    it "does not create access for a partner accepting an old invitation" do
      invitation = create(:staff_invitation)
      partner = create(:user, :super_agent, email: invitation.email)

      expect { invitation.accept!(partner) }.to raise_error(ActiveRecord::RecordInvalid)

      expect(partner.user_hotel_accesses).to be_empty
      expect(invitation.reload).not_to be_accepted
    end

    it "creates hotel access and marks the invitation accepted" do
      invitation = create(:staff_invitation)
      user = create(:user, email: invitation.email, account: invitation.account)

      expect { invitation.accept!(user) }.to change(UserHotelAccess, :count).by(1)

      expect(invitation).to be_accepted
      expect(user.user_hotel_accesses.last.role).to eq(invitation.role)
    end
  end
end
