# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StaffInvitations::ResendService do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account) }
  let(:user) { create(:user, account: account) }
  let(:role) { create(:role, account: account) }
  let(:invitation) { create(:staff_invitation, account: account, hotel: hotel, role: role) }

  subject { described_class.new(invitation, user) }

  describe '#call' do
    it 'refreshes the invitation token and sends an email' do
      old_digest = invitation.token_digest

      expect(StaffInvitationMailer).to receive(:invite).with(invitation, kind_of(String)).and_call_original
      expect {
        subject.call
      }.to have_enqueued_job(ActionMailer::MailDeliveryJob)

      expect(invitation.reload.token_digest).not_to eq(old_digest)
      expect(invitation.invited_by_user).to eq(user)
    end

    it 'returns true on success' do
      expect(subject.call).to be true
    end

    it 'returns false on failure' do
      allow(invitation).to receive(:refresh!).and_raise(StandardError, 'Failed')
      expect(subject.call).to be false
    end
  end
end
