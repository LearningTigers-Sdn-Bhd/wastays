# frozen_string_literal: true

class CorporateInvitationMailer < ApplicationMailer
  def invite(invitation, token)
    @invitation = invitation
    @hotel = invitation.hotel
    @inviter = invitation.invited_by_user
    @accept_url = corporate_invitation_url(token)
    @expires_at = invitation.expires_at

    attachments.inline["long-logo.png"] = File.read(Rails.root.join("app/assets/images/logo/long-logo.png"))

    mail(to: invitation.email, subject: "#{@hotel.name} invited you to connect a Corporate Account")
  end
end
