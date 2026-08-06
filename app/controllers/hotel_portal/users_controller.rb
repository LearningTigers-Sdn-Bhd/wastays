# frozen_string_literal: true

module HotelPortal
  class UsersController < HotelPortal::SettingsBaseController
    include StaffAssignableRoles
    include SheetActionCompletion

    before_action :authorize_manage_users!
    before_action :set_hotel_access, only: %i[edit update status destroy]
    before_action :authorize_manage_account!, only: :destroy

    def index
      @presenter = HotelPortal::StaffManagementPresenter.new(
        hotel: current_hotel,
        current_user: current_user
      )
    end

    def new
      @invitation = current_hotel.staff_invitations.build
      render layout: false
    end

    def create
      role_id = staff_invitation_params[:role_id]
      role = assignable_role(role_id)

      # Assignability is an authorization question, so it is answered here rather
      # than in the service — which would otherwise report a chosen-but-refused
      # role as a missing one.
      return reject_invitation("Selected role cannot be assigned.") if role_id.present? && role.blank?

      result = StaffInvitations::CreateService.new(
        hotel: current_hotel,
        invited_by: current_user,
        email: staff_invitation_params[:email],
        role: role
      ).call

      if result.success?
        finish_sheet("Invitation sent to #{result.invitation.email}.")
      else
        @invitation = result.invitation
        render :new, layout: false, status: :unprocessable_content
      end
    end

    def edit
      render layout: false
    end

    # The edit sheet owns the role only.
    def update
      role = assignable_role(hotel_access_params[:role_id])
      return reject_access("Selected role cannot be assigned.") if role.blank?

      result = StaffAccesses::UpdateService.new(
        access: @hotel_access,
        role: role,
        current_user: current_user
      ).call

      if result.success?
        finish_sheet("#{@hotel_access.user.name}'s role updated.")
      else
        reject_access(result.error)
      end
    end

    # The listing row's status switch owns revoke and reactivate. It targets the
    # whole page rather than a frame, so both outcomes land back on the list.
    def status
      result = StaffAccesses::UpdateService.new(
        access: @hotel_access,
        active: ActiveModel::Type::Boolean.new.cast(hotel_access_params[:active]),
        current_user: current_user
      ).call

      if result.success?
        notice = @hotel_access.active? ? "restored" : "revoked"
        redirect_to hotel_users_path(current_hotel), notice: "#{@hotel_access.user.name}'s access was #{notice}."
      else
        redirect_to hotel_users_path(current_hotel), alert: result.error
      end
    end

    def destroy
      result = StaffAccesses::DestroyService.new(
        access: @hotel_access,
        current_user: current_user
      ).call

      if result.success?
        redirect_to hotel_users_path(current_hotel), notice: "#{@hotel_access.user.name}'s access was permanently deleted."
      else
        redirect_to hotel_users_path(current_hotel), alert: result.error
      end
    end

    private

    def authorize_manage_users!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_users", hotel: current_hotel)
    end

    def authorize_manage_account!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?(
        UserHotelAccess::ACCOUNT_MANAGEMENT_PERMISSION,
        hotel: current_hotel
      )
    end

    def set_hotel_access
      @hotel_access = current_hotel.user_hotel_accesses.includes(role: :permissions).find(params[:id])
    end

    def available_roles
      assignable_roles
    end
    helper_method :available_roles

    def reject_invitation(message)
      @invitation = current_hotel.staff_invitations.build(email: staff_invitation_params[:email])
      @invitation.errors.add(:base, message)
      render :new, layout: false, status: :unprocessable_content
    end

    def reject_access(message)
      @error = message
      render :edit, layout: false, status: :unprocessable_content
    end

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
      params.fetch(:staff_invitation, params).permit(:email, :role_id)
    end

    def hotel_access_params
      params.fetch(:user_hotel_access, params).permit(:role_id, :active)
    end
  end
end
