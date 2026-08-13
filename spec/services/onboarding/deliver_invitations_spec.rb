# frozen_string_literal: true

require "rails_helper"

RSpec.describe Onboarding::DeliverInvitations do
  let(:hotel) { create(:hotel, status: "setup") }
  let(:actor) { create(:user, account: hotel.account) }

  before { HotelOps::SeedAccountRoles.call(hotel.account) }

  def role = hotel.account.roles.find_by!(slug: "front_desk")

  def staff_draft(send_invitation:, email: "new@example.com")
    hotel.onboarding_staff_drafts.create!(
      name: "Aliya", email: email, role: role, send_invitation: send_invitation
    )
  end

  def corporate_draft(send_invitation:, email: "accounts@acme.com")
    hotel.onboarding_corporate_drafts.create!(
      email: email, company_name: "Acme Sdn Bhd", account_type: "company",
      relationship_type: "direct_bill", credit_currency: "MYR", send_invitation: send_invitation
    )
  end

  describe "a draft the owner chose not to send" do
    it "becomes an invitation that was never emailed" do
      draft = staff_draft(send_invitation: false)

      expect {
        result = described_class.call(hotel: hotel, actor: actor)
        expect(result.success?).to be(true)
        expect(result).to have_attributes(sent_count: 0, held_count: 1, failures: [])
      }.not_to have_enqueued_mail(StaffInvitationMailer, :invite)

      invitation = hotel.staff_invitations.sole
      expect(invitation.last_sent_at).to be_nil
      expect(invitation).to be_held
      expect(draft.reload.invitation_id).to eq(invitation.id)
    end

    it "keeps listing the person after the unstarted expiry window passes" do
      staff_draft(send_invitation: false)
      described_class.call(hotel: hotel, actor: actor)

      travel_to(8.days.from_now) do
        expect(hotel.staff_invitations.listable).to be_present
        expect(hotel.staff_invitations.pending).to be_empty
      end
    end
  end

  describe "a draft the owner chose to send" do
    it "is emailed and starts its expiry clock" do
      expect {
        result = described_class.call(hotel: hotel, actor: actor) if staff_draft(send_invitation: true)
        expect(result).to have_attributes(sent_count: 1, held_count: 0)
      }.to have_enqueued_mail(StaffInvitationMailer, :invite).once

      expect(hotel.staff_invitations.sole.last_sent_at).to be_present
    end
  end

  describe "corporate drafts" do
    it "holds and sends by the same switch" do
      corporate_draft(send_invitation: false, email: "held@acme.com")
      corporate_draft(send_invitation: true, email: "sent@acme.com")

      expect {
        result = described_class.call(hotel: hotel, actor: actor)
        expect(result).to have_attributes(sent_count: 1, held_count: 1)
      }.to have_enqueued_mail(CorporateInvitationMailer, :invite).once

      expect(hotel.corporate_invitations.find_by(email: "held@acme.com").last_sent_at).to be_nil
      expect(hotel.corporate_invitations.find_by(email: "sent@acme.com").last_sent_at).to be_present
    end

    it "reports an ineligible company instead of taking the whole run down with it" do
      existing = create(:user, :corporate, email: "linked@acme.com")
      create(:hotel_corporate_account, hotel: hotel, corporate_account: existing.account, status: "active")
      corporate_draft(send_invitation: true, email: "linked@acme.com")
      corporate_draft(send_invitation: true, email: "fine@acme.com")

      result = described_class.call(hotel: hotel, actor: actor)

      expect(result.failures.map { |failure| failure[:email] }).to eq([ "linked@acme.com" ])
      expect(result.sent_count).to eq(1)
      expect(hotel.onboarding_corporate_drafts.undelivered.pluck(:email)).to eq([ "linked@acme.com" ])
    end
  end

  # The whole reason drafts carry a delivery marker: submission has to be safe
  # to repeat after a partial failure.
  it "invites nobody a second time when run again" do
    staff_draft(send_invitation: true)
    corporate_draft(send_invitation: true)
    described_class.call(hotel: hotel, actor: actor)

    expect {
      expect {
        result = described_class.call(hotel: hotel, actor: actor)
        expect(result).to have_attributes(sent_count: 0, held_count: 0)
      }.not_to have_enqueued_mail(StaffInvitationMailer, :invite)
    }.not_to change(Invitation, :count)
  end
end
