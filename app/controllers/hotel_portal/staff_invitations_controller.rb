# frozen_string_literal: true

module HotelPortal
  class StaffInvitationsController < HotelPortal::SettingsBaseController
    include StaffAssignableRoles
    before_action :authorize_manage_users!
    before_action :set_invitation, only: %i[update destroy resend]

    def update
      role = assignable_role(staff_invitation_params[:role_id])

      if role && @invitation.update(role: role)
        redirect_to hotel_users_path(current_hotel), notice: "Invitation role updated successfully."
      else
        alert = role ? @invitation.errors.full_messages.to_sentence : "Selected role cannot be assigned."
        redirect_to hotel_users_path(current_hotel), alert: alert
      end
    end

    def destroy
      @invitation.destroy
      redirect_to hotel_users_path(current_hotel), notice: "Invitation revoked successfully."
    end

    def resend
      if StaffInvitations::ResendService.new(@invitation, current_user).call
        redirect_to hotel_users_path(current_hotel), notice: "Invitation resent to #{@invitation.email}."
      else
        redirect_to hotel_users_path(current_hotel), alert: "Failed to resend invitation."
      end
    end

    private

    def authorize_manage_users!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_users", hotel: current_hotel)
    end

    def set_invitation
      @invitation = current_hotel.staff_invitations.pending.find(params[:id])
    end

    def staff_invitation_params
      params.fetch(:staff_invitation, params).permit(:role_id)
    end
  end
end
