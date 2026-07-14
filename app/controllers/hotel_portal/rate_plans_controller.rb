# frozen_string_literal: true

class HotelPortal::RatePlansController < HotelPortal::BaseController
  before_action :authorize!
  before_action :set_rate_plan, only: %i[destroy]

  def create
    @rate_plan = current_hotel.rate_plans.build(rate_plan_params)
    @rate_plan.currency = current_hotel.default_currency || "MYR"

    if @rate_plan.save
      # Associate selected room types
      room_type_ids = params[:room_type_ids] || []
      room_type_ids.reject(&:blank?).each do |rt_id|
        @rate_plan.room_type_rate_plans.create(room_type_id: rt_id)
      end

      redirect_to hotel_rates_settings_path(current_hotel), notice: "Rate plan '#{@rate_plan.name}' created successfully."
    else
      redirect_to hotel_rates_settings_path(current_hotel), alert: "Failed to create rate plan: #{@rate_plan.errors.full_messages.to_sentence}"
    end
  end

  def destroy
    if @rate_plan.special_tier? || @rate_plan.name.to_s.strip.downcase == "standard rate"
      redirect_to hotel_rates_settings_path(current_hotel), alert: "System rate plans cannot be deleted."
      return
    end

    if @rate_plan.destroy
      redirect_to hotel_rates_settings_path(current_hotel), notice: "Rate plan '#{@rate_plan.name}' deleted successfully."
    else
      redirect_to hotel_rates_settings_path(current_hotel), alert: "Failed to delete rate plan."
    end
  end

  private

  def set_rate_plan
    @rate_plan = current_hotel.rate_plans.find(params[:id])
  end

  def rate_plan_params
    params.require(:rate_plan).permit(
      :name,
      :sell_mode,
      :base_occupancy,
      :extra_pax_charge,
      :single_supplement,
      :child_price_multiplier,
      :infant_price_multiplier
    )
  end

  def authorize!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
  end
end
