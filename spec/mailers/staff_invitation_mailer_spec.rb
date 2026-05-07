# frozen_string_literal: true

require "rails_helper"

RSpec.describe StaffInvitationMailer, type: :mailer do
  let(:token) { "invite-token" }
  let(:invitation) { create(:staff_invitation, email: "staff@example.com") }

  subject(:mail) { described_class.invite(invitation, token) }

  it "sends to the invited email" do
    expect(mail.to).to eq([ "staff@example.com" ])
  end

  it "includes the hotel name in the subject" do
    expect(mail.subject).to include(invitation.hotel.name)
  end

  it "includes the accept invitation URL" do
    expect(mail.body.encoded).to include("/staff-invitations/#{token}")
  end
end
