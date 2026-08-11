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
      @presenter = OnboardingPresenter.new(
        hotel: current_hotel,
        navigation: @navigation,
        current_entry: @current_entry
      )
    end

    def update
      return redirect_read_only if pending_review?

      case params.require(:navigation_action)
      when "save_draft" then save_draft
      when "save_continue" then save_and_continue
      when "skip" then skip_section
      else head :unprocessable_entity
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
      redirect_to onboarding_path(destination), notice: "Step skipped for now."
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
