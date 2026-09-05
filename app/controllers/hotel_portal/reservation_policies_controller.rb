# frozen_string_literal: true

module HotelPortal
  # The four stay-event policies are seeded, never created or destroyed — a hotel
  # cannot invent a fifth kind of stay event — so this only edits.
  class ReservationPoliciesController < SettingsBaseController
    include SheetActionCompletion

    before_action :authorize!
    before_action :set_policy

    def edit
      @policy.cancellation_tiers.build(pricing_type: "percentage", percentage_basis: "total_stay") if seed_tier?
      render layout: false
    end

    def update
      result = ReservationPolicies::Save.call(policy: @policy, attributes: policy_params)
      if result.success?
        complete_sheet_action(destination: destination, notice: "#{@policy.policy_type_label} policy updated.",
          frame: turbo_frame_request_id.presence || "settings_action_sheet")
      else
        @policy.cancellation_tiers.build(pricing_type: "percentage", percentage_basis: "total_stay") if seed_tier?
        render :edit, formats: :html, layout: false, status: :unprocessable_content
      end
    end

    def update_status
      @policy.update!(active: ActiveModel::Type::Boolean.new.cast(params.require(:active)))
      redirect_to destination, notice: "#{@policy.policy_type_label} policy status updated."
    end

    private

    def authorize!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
    end

    def set_policy
      ReservationPolicies::EnsureDefaults.call(current_hotel)
      @policy = current_hotel.hotel_reservation_policies.includes(:transaction_code, :cancellation_tiers).find(params[:id])
    end

    # A cancellation sheet never shows an empty tier table — an empty repeater
    # reads as "there is nothing to configure here" rather than "add your first band".
    def seed_tier?
      @policy.cancellation? && @policy.cancellation_tiers.reject(&:marked_for_destruction?).empty?
    end

    def destination
      hotel_room_revenue_path(current_hotel, tab: "reservation_policies")
    end

    def policy_params
      params.require(:hotel_reservation_policy).permit(
        :active, :pricing_type, :rate_value, :percentage_basis, :allow_amount_override,
        :description, :refund_processing_days, :refund_method,
        cancellation_tiers_attributes: %i[id days_before_arrival pricing_type rate_value percentage_basis _destroy]
      )
    end
  end
end
