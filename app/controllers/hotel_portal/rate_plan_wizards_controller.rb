# frozen_string_literal: true

module HotelPortal
  # Creating a rate plan, one decision at a time.
  #
  # Only creating. Editing an existing plan is a different job with a different
  # shape — you arrive knowing what you came to change — and it keeps the sheet
  # it already has.
  #
  # The draft lives in the session rather than in draft rows: nothing half-priced
  # should be reachable by the booking engine, and abandoning the flow should
  # leave no trace to clean up. It is a few hundred bytes of plain values, well
  # inside the cookie store's budget for a realistic property.
  class RatePlanWizardsController < HotelPortal::BaseController
    include SheetActionCompletion

    SESSION_KEY = "rate_plan_wizard"

    before_action :authorize!
    before_action :load_wizard

    def start
      reset_draft
      redirect_to step_path(RatePlanWizard::STEP_DETAILS)
    end

    def show
      return redirect_to step_path(@wizard.first_incomplete_step) unless viewable_step?

      prepare_step
      render layout: false
    end

    def update
      return redirect_to step_path(@wizard.first_incomplete_step) unless @wizard.step_exists?(step)

      step == RatePlanWizard::STEP_DETAILS ? submit_details : submit_room
    end

    def create
      result = RatePlans::CreateFromWizard.call(wizard: @wizard)

      if result.rate_plan
        reset_draft
        finish_sheet(notice: "Rate plan '#{result.rate_plan.name}' created. Set date-specific prices under Rates & Availability.")
      else
        redirect_to step_path(@wizard.first_incomplete_step), alert: result.error
      end
    end

    def destroy
      reset_draft
      finish_sheet(notice: "New rate plan discarded.")
    end

    private

    def step = params[:step].to_s

    def submit_details
      @wizard.assign_details(details_params)

      if @wizard.details_valid?
        save_draft
        redirect_to step_path(@wizard.next_step(RatePlanWizard::STEP_DETAILS))
      else
        prepare_step
        render :show, layout: false, status: :unprocessable_content
      end
    end

    def submit_room
      room_type = @wizard.room_type_for_step(step)
      @pricing = @wizard.assign_room(room_type, room_params)

      if @pricing.valid?
        @wizard.apply_to_all_rooms(room_type) if params[:apply_to_all].present?
        save_draft
        redirect_to step_path(@wizard.next_step(step))
      else
        prepare_step
        render :show, layout: false, status: :unprocessable_content
      end
    end

    # Closes the sheet (when the request came from one) and lands back on the
    # rates settings page. Mirrors HotelPortal::RatePlansController#finish_sheet.
    def finish_sheet(notice:)
      complete_sheet_action(
        destination: hotel_rates_settings_path(current_hotel),
        notice: notice,
        frame: turbo_frame_request_id.presence || "settings_action_sheet"
      )
    end

    # A step is reachable once every step before it is answered. Deep-linking
    # past a gap lands on the gap instead, so the review step can never be shown
    # a draft it cannot save.
    def viewable_step?
      return false unless @wizard.step_exists?(step)

      furthest = @wizard.step_index(@wizard.first_incomplete_step).to_i
      @wizard.step_index(step).to_i <= furthest
    end

    def prepare_step
      @step = step
      @room_type = @wizard.room_type_for_step(@step)
      @pricing ||= copied_pricing || (@room_type && @wizard.room_pricing(@room_type))
    end

    # "Copy from" pre-fills the form from a category already answered without
    # committing anything — the values are only kept if this step is submitted.
    def copied_pricing
      return if @room_type.blank? || params[:copy_from].blank?

      source = @wizard.answered_room_types(excluding: @room_type).find { |rt| rt.id == params[:copy_from].to_i }
      return if source.blank?

      RatePlanWizard::RoomPricing.from_h(
        @wizard.to_h.dig("rooms", source.id.to_s),
        room_type: @room_type,
        sells_per_person: current_hotel.sells_per_person?
      )
    end

    def step_path(target)
      hotel_rate_plan_wizard_step_path(current_hotel, target || RatePlanWizard::STEP_REVIEW)
    end

    def load_wizard
      @wizard = RatePlanWizard.new(hotel: current_hotel, data: session[SESSION_KEY])
    end

    def save_draft
      session[SESSION_KEY] = @wizard.to_h
    end

    def reset_draft
      session.delete(SESSION_KEY)
      @wizard = RatePlanWizard.new(hotel: current_hotel)
    end

    def details_params
      params.require(:rate_plan).permit(
        :name, :description, :base_occupancy, :extra_pax_charge, :child_price_multiplier,
        room_type_ids: [],
        rate_plan_age_bands_attributes: [ :min_age, :max_age, :pricing_mode, :price_value, :label, :position, :_destroy ]
      )
    end

    def room_params
      params.require(:room_pricing).permit(
        :rate_mode, :default_rate, :derive_mode, :derive_value, :primary_occupancy,
        :increase_by, :increase_unit, :decrease_by, :decrease_unit,
        prices: {}
      )
    end

    def authorize!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
    end
  end
end
