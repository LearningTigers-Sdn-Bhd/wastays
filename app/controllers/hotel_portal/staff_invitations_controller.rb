# frozen_string_literal: true

module HotelPortal
  class StaffInvitationsController < HotelPortal::BaseController
    include StaffAssignableRoles
    before_action :authorize_manage_users!
    before_action :set_invitation, only: %i[update destroy resend]

    def update
      role_id = params[:role_id] || params.dig(:staff_invitation, :role_id)
      role = assignable_role(role_id)

      unless role
        redirect_to hotel_users_path(current_hotel), alert: "Selected role cannot be assigned."
        return
      end

      if @invitation.update(role: role)
        redirect_to hotel_users_path(current_hotel), notice: "Invitation role updated successfully."
      else
        redirect_to hotel_users_path(current_hotel), alert: @invitation.errors.full_messages.to_sentence
      end
    end

    def destroy
      @invitation.destroy
      redirect_to hotel_users_path(current_hotel), notice: "Invitation revoked successfully."
    end

    def resend
      token = @invitation.refresh!(role: @invitation.role, invited_by_user: current_user)
      StaffInvitationMailer.invite(@invitation, token).deliver_later
      redirect_to hotel_users_path(current_hotel), notice: "Invitation resent to #{@invitation.email}."
    end

    private

    def authorize_manage_users!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_users", hotel: current_hotel)
    end

    def set_invitation
      @invitation = current_hotel.staff_invitations.pending.find(params[:id])
    end
  end
end
