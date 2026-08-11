# frozen_string_literal: true

module HotelPortal
  class OnboardingController < BaseController
    layout "onboarding"

    before_action :authorize_onboarding!
    before_action :build_navigation
    before_action :set_current_entry, except: :index
    before_action :redirect_locked_section, only: :show

    def index
      redirect_to onboarding_path(@navigation.resume_entry)
    end

    def show
      prepare_section
    end

    def update
      return redirect_read_only if pending_review?

      if phase_four_section?
        update_phase_four_section
      else
        update_placeholder_section
      end
    end

    private

    def authorize_onboarding!
      authorize current_hotel, :update?, policy_class: HotelPolicy
    end

    def build_navigation
      @navigation = Onboarding::NavigationState.new(hotel: current_hotel).call
    end

    def set_current_entry
      @current_entry = @navigation.fetch(params[:section_key])
    rescue KeyError
      raise ActiveRecord::RecordNotFound
    end

    def redirect_locked_section
      return if @current_entry.available

      redirect_to onboarding_path(@navigation.resume_entry),
                  alert: "Complete the earlier onboarding steps before opening this page."
    end

    def prepare_section(staff_entries: nil)
      @presenter = OnboardingPresenter.new(
        hotel: current_hotel,
        navigation: @navigation,
        current_entry: @current_entry
      )

      case @current_entry.definition.key
      when "property_profile"
        @photo_queue = HotelPortal::PhotoQueue.new(current_hotel, session)
        @profile_presenter = HotelPortal::ProfilePresenter.new(current_hotel, @photo_queue, view_context)
      when "roles_permissions"
        @preset_roles = preset_roles.includes(:permissions)
      when "staff_setup"
        @staff_roles = preset_roles
        @staff_entries = staff_entries || current_hotel.onboarding_staff_drafts.includes(:role).order(:created_at, :id).map do |draft|
          {
            "name" => draft.name,
            "email" => draft.email,
            "role_id" => draft.role_id.to_s,
            "role_slug" => draft.role.slug,
            "role_name" => draft.role.name
          }
        end
        @staff_entries = @staff_entries + [ {} ] unless @presenter.read_only?
      end
    end

    def update_phase_four_section
      action = params.require(:navigation_action)
      return skip_staff_setup if action == "skip" && @current_entry.definition.key == "staff_setup"
      return head :unprocessable_entity unless action.in?(%w[save_draft save_continue])

      complete = action == "save_continue"
      result =
        case @current_entry.definition.key
        when "property_profile"
          Onboarding::SavePropertyProfile.new(
            hotel: current_hotel,
            params: params,
            actor: current_user,
            complete: complete
          ).call
        when "roles_permissions"
          save_role_review(complete)
        when "staff_setup"
          Onboarding::SaveStaffDrafts.new(
            hotel: current_hotel,
            actor: current_user,
            entries: params[:staff_entries] || {},
            complete: complete
          ).call
        end

      return render_phase_four_error(result) unless result.success?

      build_navigation
      destination = complete ? (@navigation.next_entry(@current_entry.definition.key) || @navigation.fetch(@current_entry.definition.key)) : @navigation.fetch(@current_entry.definition.key)
      notice = complete ? "Progress saved. Continue with the next step." : "Draft saved."
      redirect_to onboarding_path(destination), notice: notice
    end

    def save_role_review(complete)
      if complete
        Onboarding::ConfirmRolePresets.new(
          hotel: current_hotel,
          actor: current_user,
          confirmed: params[:confirm_presets]
        ).call
      else
        update_section("in_progress", source: "role_preset_review")
      end
    end

    def render_phase_four_error(result)
      current_hotel.assign_attributes(property_profile_params) if @current_entry.definition.key == "property_profile"
      build_navigation
      @current_entry = @navigation.fetch(@current_entry.definition.key)
      prepare_section(staff_entries: result.respond_to?(:entries) ? result.entries : nil)
      flash.now[:alert] = result.error
      render :show, status: :unprocessable_content
    end

    def property_profile_params
      return {} unless params[:hotel]

      params.require(:hotel).permit(
        :name, :description, :address, :city, :country, :star_rating,
        :google_map_link, :contact_email, :contact_phone, :whatsapp_number,
        :time_zone, :default_currency, amenities: []
      )
    end

    def skip_staff_setup
      result = Onboarding::DecideNoAdditionalStaff.new(hotel: current_hotel, actor: current_user).call
      return render_phase_four_error(result) unless result.success?

      build_navigation
      destination = @navigation.next_entry(@current_entry.definition.key) || @navigation.fetch(@current_entry.definition.key)
      redirect_to onboarding_path(destination), notice: "No additional staff will be invited for now."
    end

    def update_placeholder_section
      case params.require(:navigation_action)
      when "save_draft" then save_draft
      when "save_continue" then save_and_continue
      when "skip" then skip_section
      else head :unprocessable_entity
      end
    end

    def save_draft
      unless @current_entry.record.resolved?
        result = update_section("in_progress", source: "onboarding_shell")
        return redirect_result_error(result) unless result.success?
      end

      redirect_to onboarding_path(@current_entry), notice: "Draft saved."
    end

    def save_and_continue
      result = update_section("complete", source: "onboarding_shell", placeholder: true)
      return redirect_result_error(result) unless result.success?

      build_navigation
      destination = @navigation.next_entry(@current_entry.definition.key) || @navigation.fetch(@current_entry.definition.key)
      redirect_to onboarding_path(destination), notice: "Progress saved. Continue with the next step."
    end

    def skip_section
      result = update_section("skipped", source: "onboarding_shell")
      return redirect_result_error(result) unless result.success?

      build_navigation
      destination = @navigation.next_entry(@current_entry.definition.key) || @navigation.fetch(@current_entry.definition.key)
      notice = @current_entry.definition.key == "staff_setup" ? "No additional staff will be invited for now." : "Step skipped for now."
      redirect_to onboarding_path(destination), notice: notice
    end

    def update_section(state, metadata)
      Onboarding::UpdateSection.new(
        hotel: current_hotel,
        section_key: @current_entry.definition.key,
        state: state,
        actor: current_user,
        metadata: metadata
      ).call
    end

    def preset_roles
      current_hotel.account.roles.where(slug: Onboarding::ConfirmRolePresets::PRESET_SLUGS)
                   .order(Arel.sql("CASE slug WHEN 'hotel_owner' THEN 0 WHEN 'general_manager' THEN 1 WHEN 'front_desk' THEN 2 WHEN 'housekeeper' THEN 3 ELSE 4 END"))
    end

    def phase_four_section?
      @current_entry.definition.key.in?(%w[property_profile roles_permissions staff_setup])
    end

    def redirect_result_error(result)
      redirect_to onboarding_path(@current_entry), alert: result.error
    end

    def redirect_read_only
      redirect_to onboarding_path(@current_entry), alert: "Onboarding is read-only while this property is pending review."
    end

    def pending_review?
      Onboarding::LifecycleCompatibility.canonical_status(current_hotel.status) == "pending_review"
    end

    def onboarding_path(entry)
      hotel_onboarding_section_path(current_hotel, section_key: entry.definition.route_name)
    end
  end
end
