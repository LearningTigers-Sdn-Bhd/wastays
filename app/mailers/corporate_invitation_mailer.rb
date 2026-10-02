# frozen_string_literal: true

class CorporateInvitationMailer < ApplicationMailer
  def invite(invitation, token)
    @invitation = invitation
    @hotel = invitation.hotel
    @inviter = invitation.invited_by_user
    @accept_url = corporate_invitation_url(token)
    @expires_at = invitation.expires_at

    attachments.inline["long-logo.png"] = File.read(Rails.root.join("app/assets/images/logo/long-logo.png"))

    claimed = invitation.hotel_corporate_account&.corporate_account&.name
    subject = claimed ? "#{@hotel.name} invited you to manage #{claimed}" : "#{@hotel.name} invited you to connect a Corporate Account"
    mail(to: invitation.email, subject: subject)
  end
end
