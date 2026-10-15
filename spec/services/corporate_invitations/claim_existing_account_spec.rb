# frozen_string_literal: true

require "rails_helper"

# The reservation importer creates a corporate account for every travel agent it
# finds, with the bookings already on it and nobody able to sign in. Inviting a
# contact to *that* account has to give them a login inside it -- not make a
# second account that has none of the bookings.
RSpec.describe "Claiming an existing corporate account by invitation" do
  let(:hotel_account) { create(:account) }
  let(:hotel) { create(:hotel, account: hotel_account) }
  let(:inviter) { create(:user, account: hotel_account) }
  let(:agency_account) { create(:account, :corporate, name: "PERFECT VACATION SDN.BHD") }
  let!(:relationship) do
    create(:hotel_corporate_account, hotel: hotel, corporate_account: agency_account, account_type: "travel_agent")
  end
  let(:user_attributes) { { name: "Sabrina Chin", password: "password123", password_confirmation: "password123" } }

  def invite(email: "sabrina@perfect.test", id: relationship.id)
    CorporateInvitations::CreateService.new(
      hotel: hotel, invited_by_user: inviter, attributes: { email: email, hotel_corporate_account_id: id }
    ).call
  end

  describe CorporateInvitations::CreateService do
    it "invites a contact to the existing account, carrying the account's own terms" do
      relationship.update!(relationship_type: "direct_bill", credit_limit: 5000, payment_terms_days: 30)

      result = invite

      expect(result).to be_success
      expect(result.invitation).to have_attributes(
        hotel_corporate_account: relationship, relationship_type: "direct_bill", credit_limit: 5000, payment_terms_days: 30
      )
      expect(result.invitation).to be_claim
    end

    it "creates no account, user or relationship until it is accepted" do
      inviter

      expect { invite }.to change(Account, :count).by(0).and change(User, :count).by(0)
                                                  .and change(HotelCorporateAccount, :count).by(0)
    end

    it "emails the invitation" do
      expect { invite }.to have_enqueued_mail(CorporateInvitationMailer, :invite)
    end

    it "refuses an account that already has a login" do
      create(:user, :corporate, account: agency_account)

      result = invite

      expect(result).not_to be_success
      expect(result.error).to include("already has a login")
    end

    it "refuses an email that already belongs to a user, who would then have two accounts" do
      create(:user, :corporate, email: "sabrina@perfect.test")

      expect(invite.error).to include("already belongs to a user")
    end

    it "refuses an account that belongs to another hotel" do
      other = create(:hotel_corporate_account)

      expect(invite(id: other.id).error).to include("could not be found")
    end

    it "reuses a pending invitation for the same account instead of stacking another" do
      first = invite(email: "old@perfect.test").invitation

      second = invite(email: "new@perfect.test").invitation

      expect(second.id).to eq(first.id)
      expect(second.email).to eq("new@perfect.test")
      expect(relationship.claim_invitations.unaccepted.count).to eq(1)
    end
  end

  describe CorporateInvitations::AcceptService do
    let(:invitation) { invite.invitation }

    it "gives the invitee a login inside the existing account, and creates nothing else" do
      invitation

      expect {
        result = described_class.new(invitation: invitation, user_attributes: user_attributes).call
        expect(result).to be_success
        expect(result.user).to have_attributes(account: agency_account, email: "sabrina@perfect.test", role: "corporate")
        expect(result.relationship).to eq(relationship)
      }.to change(User, :count).by(1).and change(Account, :count).by(0).and change(HotelCorporateAccount, :count).by(0)
    end

    it "keeps the account's name and the bookings already on it" do
      booking = create(:booking, hotel: hotel, hotel_corporate_account: relationship)

      described_class.new(invitation: invitation, user_attributes: user_attributes).call

      expect(agency_account.reload.name).to eq("PERFECT VACATION SDN.BHD")
      expect(booking.reload.hotel_corporate_account).to eq(relationship)
    end

    it "records the contact on the relationship when it had none" do
      relationship.update!(contact_email: nil)

      described_class.new(invitation: invitation, user_attributes: user_attributes).call

      expect(relationship.reload.contact_email).to eq("sabrina@perfect.test")
    end

    it "marks the invitation accepted" do
      described_class.new(invitation: invitation, user_attributes: user_attributes).call

      expect(invitation.reload).to be_accepted
    end

    it "refuses when someone else claimed the account first" do
      invitation
      create(:user, :corporate, account: agency_account)

      result = described_class.new(invitation: invitation, user_attributes: user_attributes).call

      expect(result).not_to be_success
      expect(result.error).to include("already been claimed")
      expect(invitation.reload).not_to be_accepted
    end

    it "reports a weak password rather than half-creating anything" do
      invitation

      expect {
        result = described_class.new(invitation: invitation, user_attributes: user_attributes.merge(password: "x", password_confirmation: "y")).call
        expect(result).not_to be_success
      }.not_to change(User, :count)
      expect(invitation.reload).not_to be_accepted
    end
  end

  describe HotelCorporateAccount do
    it "is unclaimed until someone has a login to it" do
      expect(relationship).to be_unclaimed

      create(:user, :corporate, account: agency_account)

      expect(relationship.reload).not_to be_unclaimed
    end
  end
end
