# frozen_string_literal: true

class Public::OwnerPasswordResetsController < ApplicationController
  layout "auth"

  def show
    @reset = OwnerPasswordReset.find_valid(params[:token])
    redirect_to login_path, alert: "This password reset link is invalid or expired." unless @reset
  end

  def update
    @reset = OwnerPasswordReset.find_by(token_digest: Digest::SHA256.hexdigest(params[:token].to_s))
    unless @reset
      redirect_to login_path, alert: "This password reset link is invalid or expired."
      return
    end

    @reset.with_lock do
      unless @reset.consumed_at.nil? && @reset.expires_at.future?
        redirect_to login_path, alert: "This password reset link is invalid or expired."
        return
      end

      Admin::Hotels::ChangeOwnerPassword.call(
        user: @reset.user, password: params[:password], password_confirmation: params[:password_confirmation]
      )
    end
    redirect_to login_path, notice: "Password updated. Sign in with your new password."
  rescue ActiveRecord::RecordInvalid => e
    @error = e.record.errors.full_messages.to_sentence
    render :show, status: :unprocessable_content
  end
end
