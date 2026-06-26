# frozen_string_literal: true

module HotelPortal
  class CorporateInvitationsController < HotelPortal::BaseController
    before_action :authorize_manage_corporate_accounts!
    before_action :set_invitation

    def resend
      if CorporateInvitations::ResendService.new(invitation: @invitation, invited_by_user: current_user).call
        redirect_to hotel_corporate_accounts_path(current_hotel), notice: "Corporate invitation resent to #{@invitation.email}."
      else
        redirect_to hotel_corporate_accounts_path(current_hotel), alert: "Unable to resend this invitation."
      end
    end

    def destroy
      @invitation.destroy!
      redirect_to hotel_corporate_accounts_path(current_hotel), notice: "Corporate invitation revoked."
    end

    private

    def authorize_manage_corporate_accounts!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_corporate_accounts", hotel: current_hotel)
    end

    def set_invitation
      @invitation = current_hotel.corporate_invitations.unaccepted.find(params[:id])
    end
  end
end
