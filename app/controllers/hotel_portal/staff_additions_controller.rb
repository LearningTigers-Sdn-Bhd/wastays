# frozen_string_literal: true

module HotelPortal
  class StaffAdditionsController < SettingsBaseController
    include StaffAssignableRoles
    include SheetActionCompletion

    before_action :authorize!
    before_action :prepare_form

    def new
      render :new, formats: :html, layout: false
    end

    def lookup
      resolve_email
      render_form(status: @lookup_ready ? :ok : :unprocessable_content)
    end

    def create
      role = assignable_role(@attributes[:role_id])
      result = if role
        StaffAccesses::CreateService.new(hotel: current_hotel, email: @attributes[:email],
          name: @attributes[:name], role: role).call
      else
        StaffAccesses::CreateService::Result.failure("Selected role cannot be assigned.")
      end

      if result.success?
        if result.created
          @credential_user = result.user
          response.headers["Cache-Control"] = "no-store"
          respond_to do |format|
            format.turbo_stream { render turbo_stream: turbo_stream.update(sheet_frame, partial: "hotel_portal/staff_passwords/credentials") }
            format.html { render "hotel_portal/staff_passwords/show", layout: false }
          end
        else
          complete_sheet_action(destination: hotel_users_path(current_hotel),
            notice: "#{result.user.name} added to this property.", frame: sheet_frame)
        end
      else
        resolve_email
        @errors << result.error unless @errors.include?(result.error)
        render_form(status: :unprocessable_content)
      end
    end

    private

    def authorize!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_users", hotel: current_hotel)
    end

    def prepare_form
      @attributes = params.fetch(:staff_addition, ActionController::Parameters.new).permit(:email, :name, :role_id).to_h.symbolize_keys
      @errors = []
    end

    def resolve_email
      result = StaffAccesses::LookupService.new(hotel: current_hotel, email: @attributes[:email]).call
      @lookup_ready = result.success?
      @existing_user = result.user
      @outstanding_invitation = result.outstanding_invitation
      @errors << result.error unless result.success?
    end

    def available_roles
      assignable_roles
    end
    helper_method :available_roles

    def render_form(status:)
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.update(sheet_frame, partial: "hotel_portal/staff_additions/form"), status: status }
        format.html { render :new, layout: false, status: status }
      end
    end

    def sheet_frame
      turbo_frame_request_id.presence || "settings_action_sheet"
    end
  end
end
