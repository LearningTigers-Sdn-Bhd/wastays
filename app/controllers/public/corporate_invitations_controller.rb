# frozen_string_literal: true

module Public
  class CorporateInvitationsController < ApplicationController
    layout "auth"

    before_action :set_invitation

    def show
      return redirect_unavailable unless @invitation&.pending?

      @existing_user = User.find_by(email: @invitation.email)
      return redirect_collision if @existing_user && !@existing_user.corporate?
      return redirect_existing_user_login if @existing_user && current_user != @existing_user

      @user = User.new(email: @invitation.email)
    end

    def update
      return redirect_unavailable unless @invitation&.pending?
      @existing_user = User.find_by(email: @invitation.email)
      return redirect_collision if @existing_user && !@existing_user.corporate?
      return redirect_existing_user_login if @existing_user&.corporate? && current_user != @existing_user

      result = CorporateInvitations::AcceptService.new(
        invitation: @invitation,
        user_attributes: user_params,
        accepting_user: current_user
      ).call

      if result.success?
        session[:user_id] = result.user.id
        redirect_to corporate_dashboard_path, notice: "Welcome to your corporate account."
      else
        @user = User.new(user_params.merge(email: @invitation.email))
        flash.now[:alert] = result.error
        render :show, status: :unprocessable_content
      end
    end

    private

    def set_invitation
      @token = params[:token].to_s
      @invitation = CorporateInvitation.find_by_token(@token)
    end

    def user_params
      params.fetch(:user, {}).permit(:account_name, :name, :password, :password_confirmation)
    end

    def redirect_unavailable
      redirect_to login_path, alert: "This invitation is invalid or has expired."
    end

    def redirect_collision
      redirect_to login_path, alert: "This invitation email belongs to a hotel staff account."
    end

    def redirect_existing_user_login
      session[:forwarding_url] = request.fullpath
      redirect_to login_path, alert: "Log in as #{@existing_user.email} to accept this corporate invitation."
    end
  end
end
