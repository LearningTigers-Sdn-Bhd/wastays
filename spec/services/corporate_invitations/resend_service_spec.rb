# frozen_string_literal: true

require "rails_helper"

RSpec.describe CorporateInvitations::ResendService do
  let(:invitation) { create(:corporate_invitation, expires_at: 1.minute.ago) }
  let(:inviter) { invitation.invited_by_user }

  it "rotates the token, extends expiry, and queues the mail" do
    old_digest = invitation.token_digest

    expect(CorporateInvitationMailer).to receive(:invite).with(invitation, kind_of(String)).and_call_original

    expect(described_class.new(invitation: invitation, invited_by_user: inviter).call).to be(true)
    expect(invitation.reload.token_digest).not_to eq(old_digest)
    expect(invitation).to be_pending
  end

  it "does not resend an accepted invitation" do
    invitation.update!(accepted_at: Time.current)

    expect(described_class.new(invitation: invitation, invited_by_user: inviter).call).to be(false)
  end
end
