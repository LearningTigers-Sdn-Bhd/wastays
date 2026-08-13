# frozen_string_literal: true

class OwnerActivationMailer < ApplicationMailer
  def activate(invitation, token)
    @invitation = invitation
    @hotel = invitation.hotel
    @activation_url = staff_invitation_url(token)
    @expires_at = invitation.expires_at

    mail(to: invitation.email, subject: "Activate your WAStays owner account for #{@hotel.name}")
  end
end
