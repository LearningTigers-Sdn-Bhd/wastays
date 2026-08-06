# frozen_string_literal: true

require "rails_helper"

RSpec.describe StaffInvitations::CreateService do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account) }
  let(:role) { create(:role, account: account) }
  let(:invited_by) { create(:user, account: account) }

  def service(email: "new.staff@example.com", role: self.role, hotel: self.hotel)
    described_class.new(hotel: hotel, invited_by: invited_by, email: email, role: role)
  end

  it "issues a pending invitation for the property" do
    result = service.call

    expect(result.success?).to be(true)
    expect(result.invitation).to have_attributes(
      email: "new.staff@example.com", hotel: hotel, account: account, role: role, invited_by_user: invited_by
    )
    expect(result.invitation).to be_persisted
    expect(result.invitation).to be_pending
  end

  it "normalizes the email before storing it" do
    result = service(email: "  New.Staff@Example.COM  ").call

    expect(result.success?).to be(true)
    expect(result.invitation.email).to eq("new.staff@example.com")
  end

  it "stores only the digest of a freshly generated token" do
    allow(StaffInvitation).to receive(:generate_token).and_return("token-abc")

    result = service.call

    expect(result.invitation.token_digest).to eq(StaffInvitation.digest("token-abc"))
    expect(result.invitation.attributes).not_to include("token")
  end

  it "sets the expiry from the invitation window" do
    result = service.call

    expect(result.invitation.expires_at).to be_within(5.seconds).of(StaffInvitation::EXPIRY.from_now)
  end

  it "delivers the invitation email with the raw token" do
    allow(StaffInvitation).to receive(:generate_token).and_return("token-abc")

    expect(StaffInvitationMailer).to receive(:invite).with(kind_of(StaffInvitation), "token-abc").and_call_original

    expect { service.call }.to have_enqueued_job(ActionMailer::MailDeliveryJob)
  end

  # A re-invite refreshes the outstanding invitation rather than stacking
  # duplicates for the same email.
  it "reuses the outstanding invitation and rotates its token" do
    first = service.call.invitation
    old_digest = first.token_digest

    result = service.call

    expect(result.success?).to be(true)
    expect(result.invitation.id).to eq(first.id)
    expect(result.invitation.token_digest).not_to eq(old_digest)
    expect(hotel.staff_invitations.where(email: "new.staff@example.com").count).to eq(1)
  end

  it "applies the new role when re-inviting" do
    service.call
    other_role = create(:role, account: account)

    result = service(role: other_role).call

    expect(result.success?).to be(true)
    expect(result.invitation.role).to eq(other_role)
  end

  # An accepted invitation is history; a fresh one is issued beside it.
  it "issues a new invitation when the previous one was accepted" do
    accepted = service.call.invitation
    accepted.update!(accepted_at: Time.current)

    result = service.call

    expect(result.success?).to be(true)
    expect(result.invitation.id).not_to eq(accepted.id)
  end

  it "rejects a blank email" do
    result = service(email: "  ").call

    expect(result.success?).to be(false)
    expect(result.error).to eq("Email and role are required.")
    expect(result.invitation).not_to be_persisted
  end

  it "rejects a missing role" do
    result = service(role: nil).call

    expect(result.success?).to be(false)
    expect(result.error).to eq("Email and role are required.")
  end

  it "rejects an email belonging to a corporate user" do
    corporate = create(:user, :corporate, email: "buyer@example.com")

    result = service(email: corporate.email).call

    expect(result.success?).to be(false)
    expect(result.error).to eq("This email belongs to a corporate account. Use a separate staff email.")
  end

  it "rejects a user who already has active access to the property" do
    existing = create(:user, account: account, email: "on.staff@example.com")
    create(:user_hotel_access, user: existing, hotel: hotel, role: role)

    result = service(email: existing.email).call

    expect(result.success?).to be(false)
    expect(result.error).to eq("This user already has active access to this property.")
  end

  it "invites a user whose access to the property was deactivated" do
    existing = create(:user, account: account, email: "returning@example.com")
    create(:user_hotel_access, user: existing, hotel: hotel, role: role).deactivate!

    result = service(email: existing.email).call

    expect(result.success?).to be(true)
  end

  # Access is per property, so a user working at a sibling hotel can still be
  # invited to this one.
  it "invites a user who only has access to another property" do
    other_hotel = create(:hotel, account: account)
    existing = create(:user, account: account, email: "sibling@example.com")
    create(:user_hotel_access, user: existing, hotel: other_hotel, role: role)

    result = service(email: existing.email).call

    expect(result.success?).to be(true)
  end

  # The sheet re-renders the operator's input, so a rejection still has to come
  # back with an invitation carrying the error.
  it "returns an unsaved invitation carrying the error on rejection" do
    result = service(email: "").call

    expect(result.invitation).to be_a(StaffInvitation)
    expect(result.invitation.errors[:base]).to include("Email and role are required.")
  end

  it "returns the validation message when the record fails to save" do
    result = service(email: "not-an-email").call

    expect(result.success?).to be(false)
    expect(result.error).to include("Email")
    expect(result.invitation).not_to be_persisted
  end

  it "does not send an email when the invitation is rejected" do
    expect { service(email: "").call }.not_to have_enqueued_job(ActionMailer::MailDeliveryJob)
  end
end
