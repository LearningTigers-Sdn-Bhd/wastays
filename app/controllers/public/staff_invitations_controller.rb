# frozen_string_literal: true

module Public
  class StaffInvitationsController < ApplicationController
    layout "auth"

    before_action :set_invitation

    def show
      return redirect_unavailable unless @invitation&.pending?

      @existing_user = User.find_by(email: @invitation.email)
      return redirect_corporate_collision if @existing_user&.corporate?

      @user = User.new(email: @invitation.email, name: @invitation.name)
    end

    def update
      return redirect_unavailable unless @invitation&.pending?

      user = User.find_by(email: @invitation.email)
      return redirect_corporate_collision if user&.corporate?

      if user
        accept_invitation_for(user)
      else
        create_user_and_accept_invitation
      end
    end

    private

    def set_invitation
      @token = params[:token].to_s
      @invitation = StaffInvitation.find_by_token(@token)
    end

    def create_user_and_accept_invitation
      @user = User.new(user_params.merge(email: @invitation.email, account: @invitation.account, role: "hotel_staff"))

      if @user.save
        accept_invitation_for(@user)
      else
        @existing_user = nil
        render :show, status: :unprocessable_content
      end
    end

    def accept_invitation_for(user)
      @invitation.accept!(user)
      session[:user_id] = user.id
      redirect_to hotel_dashboard_path(@invitation.hotel), notice: "Welcome to #{@invitation.hotel.name}."
    end

    def user_params
      params.require(:user).permit(:name, :password, :password_confirmation)
    end

    def redirect_unavailable
      redirect_to login_path, alert: "This invitation is invalid or has expired."
    end

    def redirect_corporate_collision
      redirect_to login_path, alert: "This invitation email belongs to a corporate account."
    end
  end
end
