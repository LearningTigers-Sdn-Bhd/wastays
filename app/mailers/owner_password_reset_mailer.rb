# frozen_string_literal: true

class OwnerPasswordResetMailer < ApplicationMailer
  def reset(user, hotel, token)
    @user = user
    @hotel = hotel
    @reset_url = owner_password_reset_url(token:)
    attach_logo
    mail(to: user.email, subject: "Reset your WAStays password")
  end

  # Self-service "Forgot password" (no admin, no hotel context).
  def forgot(user, token)
    @user = user
    @reset_url = owner_password_reset_url(token:)
    attach_logo
    mail(to: user.email, subject: "Reset your WAStays password")
  end

  private

  def attach_logo
    attachments.inline["long-logo.png"] = File.read(Rails.root.join("app/assets/images/logo/long-logo.png"))
  end
end
