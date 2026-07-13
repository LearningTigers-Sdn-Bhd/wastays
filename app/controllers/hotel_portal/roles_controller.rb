# frozen_string_literal: true

module HotelPortal
  class RolesController < HotelPortal::BaseController
    before_action :authorize_manage_users!
    before_action -> { require_feature!("role_based_access_control") }
    before_action :set_role, only: %i[edit update destroy]
    before_action :load_permissions, only: %i[new create edit update], if: -> { false } # Removed, kept index and bulk_update calls

    def index
      @roles = current_hotel.account.roles.includes(:permissions, :user_hotel_accesses).order(:name)
      load_permissions
    end

    def bulk_update
      roles_params = params.require(:roles)
      @roles = current_hotel.account.roles.includes(:permissions).where(id: roles_params.keys)
      load_permissions

      Role.transaction do
        @roles.each do |role|
          role_data = roles_params[role.id.to_s]
          next unless role_data

          permission_ids = extract_permission_ids(role_data[:permission_ids])
          role.permission_ids = permission_ids
        end
      end

      redirect_to hotel_roles_path(current_hotel), notice: "Permissions updated successfully."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to hotel_roles_path(current_hotel), alert: "Failed to update permissions: #{e.message}"
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

    def extract_permission_ids(ids_param, role = nil)
      requested_ids = Array(ids_param).reject(&:blank?).uniq
      permitted_ids = @assignable_permissions.map(&:id).map(&:to_s)
      disallowed_ids = requested_ids - permitted_ids

      if disallowed_ids.any?
        if role
          disallowed_names = Permission.where(id: disallowed_ids).order(:name).pluck(:name).to_sentence
          role.errors.add(:permissions, "include permissions you cannot assign: #{disallowed_names}")
        end
        return nil
      end

      Permission.where(id: requested_ids).ids
    end

    def save_role
      Role.transaction do
        @role.save!
        if params[:role].key?(:permission_ids)
          load_permissions
          p_ids = extract_permission_ids(role_params[:permission_ids], @role)
          raise ActiveRecord::RecordInvalid, @role if p_ids.nil?
          @role.permission_ids = p_ids
        end
      end
      true
    rescue ActiveRecord::RecordInvalid
      false
    end
  end
end
