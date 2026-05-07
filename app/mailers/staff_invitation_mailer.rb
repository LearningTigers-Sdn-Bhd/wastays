# frozen_string_literal: true

class StaffInvitationMailer < ApplicationMailer
  def invite(invitation, token)
    @invitation = invitation
    @hotel = invitation.hotel
    @role = invitation.role
    @inviter = invitation.invited_by_user
    @accept_url = staff_invitation_url(token)
    @expires_at = invitation.expires_at

    attachments.inline["long-logo.png"] = File.read(Rails.root.join("app/assets/images/logo/long-logo.png"))

    mail(to: invitation.email, subject: "You're invited to join #{@hotel.name} on WAStays")
  end
end
