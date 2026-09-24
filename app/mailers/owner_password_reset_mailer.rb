# frozen_string_literal: true

class OwnerPasswordResetMailer < ApplicationMailer
  def reset(user, hotel, token)
    @user = user
    @hotel = hotel
    @reset_url = owner_password_reset_url(token:)
    mail(to: user.email, subject: "Reset your WAStays password")
  end
end
