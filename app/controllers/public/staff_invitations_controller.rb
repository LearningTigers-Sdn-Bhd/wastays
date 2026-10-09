# frozen_string_literal: true

module Public
  class StaffInvitationsController < ApplicationController
    layout "auth"

    before_action :set_invitation

    def show
      return redirect_unavailable unless @invitation&.pending?

      @existing_user = User.find_by(email: @invitation.email)
      return redirect_corporate_collision if @existing_user&.corporate?
      return redirect_partner_collision if @existing_user&.super_agent?

      @user = User.new(email: @invitation.email, name: @invitation.name)
    end

    def update
      return redirect_unavailable unless @invitation&.pending?

      user = User.find_by(email: @invitation.email)
      return redirect_corporate_collision if user&.corporate?
      return redirect_partner_collision if user&.super_agent?

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
      sign_in_user(user)
      redirect_to invitation_destination, notice: "Welcome to #{@invitation.hotel.name}."
    rescue ActiveRecord::RecordInvalid => e
      raise unless e.record.errors[:base].include?(StaffInvitation::PARTNER_INVITATION_ERROR)

      redirect_partner_collision
    end

    def invitation_destination
      if @invitation.role.slug == "hotel_owner" &&
         @invitation.hotel.status == "setup"
        hotel_onboarding_path(@invitation.hotel)
      else
        hotel_dashboard_path(@invitation.hotel)
      end
    end

    def user_params
      params.require(:user).permit(:name, :password, :password_confirmation)
    end

    def redirect_unavailable
      redirect_to login_path, alert: "This invitation is invalid or has expired."
    end

    def redirect_partner_collision
      redirect_to login_path, alert: StaffInvitation::PARTNER_INVITATION_ERROR
    end

    def redirect_corporate_collision
      redirect_to login_path, alert: "This invitation email belongs to a corporate account."
    end
  end
end
