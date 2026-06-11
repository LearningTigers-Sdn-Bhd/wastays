# frozen_string_literal: true

module HotelPortal
  class RolesController < HotelPortal::BaseController
    before_action :authorize_manage_users!
    before_action -> { require_feature!("role_based_access_control") }
    before_action :set_role, only: %i[edit update destroy]
    before_action :load_permissions, only: %i[new create edit update]

    def index
      @roles = current_hotel.account.roles.includes(:permissions, :user_hotel_accesses).order(:name)
    end

    def new
      @role = current_hotel.account.roles.build
    end

    def create
      @role = current_hotel.account.roles.build(role_attributes)

      if save_role
        redirect_to hotel_roles_path(current_hotel), notice: "Role created successfully."
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      @role.assign_attributes(role_attributes)

      if save_role
        redirect_to hotel_roles_path(current_hotel), notice: "Role updated successfully."
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      if @role.user_hotel_accesses.exists?
        redirect_to hotel_roles_path(current_hotel), alert: "Role cannot be deleted while staff are assigned to it."
        return
      end

      if @role.destroy
        redirect_to hotel_roles_path(current_hotel), notice: "Role deleted successfully."
      else
        redirect_to hotel_roles_path(current_hotel), alert: @role.errors.full_messages.to_sentence
      end
    end

    private

    def authorize_manage_users!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_users", hotel: current_hotel)
    end

    def set_role
      @role = current_hotel.account.roles.find(params[:id])
    end

    def load_permissions
      @assignable_permissions = Permission.order(:name).select do |permission|
        permission.slug != "manage_account" || current_user.has_permission?("manage_account")
      end
    end

    def role_params
      params.require(:role).permit(:name, permission_ids: [])
    end

    def role_attributes
      role_params.except(:permission_ids)
    end

    def permission_ids
      requested_ids = Array(role_params[:permission_ids]).reject(&:blank?).uniq
      permitted_ids = @assignable_permissions.map(&:id).map(&:to_s)
      disallowed_ids = requested_ids - permitted_ids

      if disallowed_ids.any?
        disallowed_names = Permission.where(id: disallowed_ids).order(:name).pluck(:name).to_sentence
        @role.errors.add(:permissions, "include permissions you cannot assign: #{disallowed_names}")
        return nil
      end

      Permission.where(id: requested_ids).ids
    end

    def save_role
      Role.transaction do
        permission_ids = permission_ids()
        raise ActiveRecord::RecordInvalid, @role if permission_ids.nil?

        @role.save!
        @role.permission_ids = permission_ids
      end
      true
    rescue ActiveRecord::RecordInvalid
      false
    end
  end
end
