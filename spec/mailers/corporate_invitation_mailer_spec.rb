# frozen_string_literal: true

require "rails_helper"

RSpec.describe CorporateInvitationMailer, type: :mailer do
  let(:invitation) { create(:corporate_invitation, email: "billing@acme.test") }
  let(:mail) { described_class.invite(invitation, "raw-token") }

  it "sends the corporate acceptance URL" do
    expect(mail.to).to eq([ "billing@acme.test" ])
    expect(mail.body.encoded).to include(corporate_invitation_url("raw-token"))
    expect(mail.body.encoded).to include("connect a Corporate Account")
  end
end
