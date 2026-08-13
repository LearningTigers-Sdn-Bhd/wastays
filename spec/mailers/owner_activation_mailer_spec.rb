require "rails_helper"

RSpec.describe OwnerActivationMailer, type: :mailer do
  it "sends a secure owner activation link" do
    hotel = create(:hotel)
    owner_role = create(:role, account: hotel.account, slug: "hotel_owner", name: "Hotel Owner")
    inviter = create(:user, :superadmin)
    token = StaffInvitation.generate_token
    invitation = StaffInvitation.create!(
      hotel: hotel,
      account: hotel.account,
      role: owner_role,
      invited_by_user: inviter,
      name: "Owner Name",
      email: "owner-activation@example.test",
      token_digest: StaffInvitation.digest(token),
      expires_at: 7.days.from_now
    )

    mail = described_class.activate(invitation, token)

    expect(mail.to).to eq([ "owner-activation@example.test" ])
    expect(mail.subject).to include("Activate your WAStays owner account")
    expect(mail.body.encoded).to include(token)
  end
end
