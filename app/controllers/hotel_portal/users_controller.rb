# frozen_string_literal: true

module HotelPortal
  class UsersController < HotelPortal::BaseController
    include StaffAssignableRoles
    before_action :authorize_manage_users!
    before_action :set_hotel_access, only: %i[update destroy reactivate]

    def index
      @hotel_accesses = current_hotel.user_hotel_accesses.includes(:user, :role).order(deactivated_at: :asc, created_at: :desc)
      @pending_invitations = current_hotel.staff_invitations.pending.includes(:role, :invited_by_user).order(created_at: :desc)
      @available_roles = assignable_roles
    end

    def new
      @available_roles = assignable_roles
    end

    def create
      email = params[:email].to_s.strip.downcase
      role_id = params[:role_id]

      if email.blank? || role_id.blank?
        redirect_to hotel_users_path(current_hotel), alert: "Email and Role are required."
        return
      end

      role = assignable_role(role_id)

      unless role
        redirect_to hotel_users_path(current_hotel), alert: "Selected role cannot be assigned."
        return
      end

      user = User.find_by(email: email)
      if user&.corporate?
        redirect_to hotel_users_path(current_hotel), alert: "This email belongs to a corporate account. Use a separate staff email."
        return
      end

      if user && current_hotel.user_hotel_accesses.active.exists?(user: user)
        redirect_to hotel_users_path(current_hotel), alert: "This user already has active access to this property."
        return
      end

      invitation = current_hotel.staff_invitations.find_or_initialize_by(email: email, accepted_at: nil)
      token = StaffInvitation.generate_token
      invitation.assign_attributes(
        account: current_hotel.account,
        role: role,
        invited_by_user: current_user,
        token_digest: StaffInvitation.digest(token),
        expires_at: StaffInvitation::EXPIRY.from_now
      )

      if invitation.save
        StaffInvitationMailer.invite(invitation, token).deliver_later
        redirect_to hotel_users_path(current_hotel), notice: "Invitation sent to #{email}."
      else
        redirect_to hotel_users_path(current_hotel), alert: invitation.errors.full_messages.to_sentence
      end
    end

    def update
      role_id = params[:role_id] || params.dig(:user_hotel_access, :role_id)
      role = assignable_role(role_id)

      unless role
        redirect_to hotel_users_path(current_hotel), alert: "Selected role cannot be assigned."
        return
      end

      if @hotel_access.update(role: role)
        redirect_to hotel_users_path(current_hotel), notice: "Role updated successfully."
      else
        redirect_to hotel_users_path(current_hotel), alert: @hotel_access.errors.full_messages.to_sentence
      end
    end

    def destroy
      if @hotel_access.user_id == current_user.id
        redirect_to hotel_users_path(current_hotel), alert: "You cannot revoke your own access."
        return
      end

      @hotel_access.deactivate!
      redirect_to hotel_users_path(current_hotel), notice: "Staff access revoked successfully."
    end

    def reactivate
      @hotel_access.reactivate!
      redirect_to hotel_users_path(current_hotel), notice: "Staff access reactivated successfully."
    end

    private

    def authorize_manage_users!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_users", hotel: current_hotel)
    end

    def set_hotel_access
      @hotel_access = current_hotel.user_hotel_accesses.find(params[:id])
    end
  end
end
