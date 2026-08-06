# frozen_string_literal: true

module HotelPortal
  class StaffInvitationsController < HotelPortal::SettingsBaseController
    include StaffAssignableRoles
    include SheetActionCompletion

    before_action :authorize_manage_users!
    before_action :set_invitation, only: %i[edit update destroy resend]

    def edit
      render layout: false
    end

    def update
      role = assignable_role(staff_invitation_params[:role_id])

      if role && @invitation.update(role: role)
        finish_sheet("Invitation role updated successfully.")
      else
        @error = role ? @invitation.errors.full_messages.to_sentence : "Selected role cannot be assigned."
        render :edit, layout: false, status: :unprocessable_content
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

    def available_roles
      assignable_roles
    end
    helper_method :available_roles

    def finish_sheet(notice)
      complete_sheet_action(
        destination: hotel_users_path(current_hotel),
        notice: notice,
        frame: sheet_frame
      )
    end

    def sheet_frame
      turbo_frame_request_id.presence || "settings_action_sheet"
    end

    def staff_invitation_params
      params.fetch(:staff_invitation, params).permit(:role_id)
    end
  end
end
