# frozen_string_literal: true

# Self-service "Forgot password". Always answers the same way so it can't be
# used to find out which emails have accounts. The reset itself reuses
# OwnerPasswordReset tokens and Public::OwnerPasswordResetsController.
class Public::PasswordResetRequestsController < ApplicationController
  layout "auth"

  COOLDOWN = 2.minutes

  def new
  end

  def create
    user = User.find_by(email: params[:email].to_s.strip.downcase)
    send_reset(user) if user && user.account&.status != "suspended"

    redirect_to login_path, notice: "If that email has an account, we've sent a link to reset your password."
  end

  private

  def send_reset(user)
    return if user.owner_password_resets.exists?([ "created_at > ?", COOLDOWN.ago ])

    token = OwnerPasswordReset.issue!(user)
    OwnerPasswordResetMailer.forgot(user, token).deliver_later
  end
end
