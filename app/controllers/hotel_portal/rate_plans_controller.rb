# frozen_string_literal: true

class HotelPortal::RatePlansController < HotelPortal::BaseController
  before_action :authorize!
  before_action :set_rate_plan, only: %i[edit update destroy]

  def new
    @rate_plan = current_hotel.rate_plans.build(sell_mode: default_sell_mode)
  end

  def edit
  end

  def create
    @rate_plan = current_hotel.rate_plans.build(rate_plan_params)
    @rate_plan.currency = current_hotel.default_currency || "MYR"

    if @rate_plan.save
      redirect_to hotel_rates_settings_path(current_hotel), notice: "Rate plan '#{@rate_plan.name}' created successfully."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @rate_plan.update(rate_plan_params)
      redirect_to hotel_rates_settings_path(current_hotel), notice: "Rate plan '#{@rate_plan.name}' updated successfully."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    unless @rate_plan.deletable?
      redirect_to hotel_rates_settings_path(current_hotel), alert: "This rate plan cannot be deleted."
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

  def default_sell_mode
    current_hotel.pax_pricing_only? ? "per_person" : "per_room"
  end

  def rate_plan_params
    params.require(:rate_plan).permit(
      :name,
      :sell_mode,
      :base_occupancy,
      :extra_pax_charge,
      :single_supplement,
      :child_price_multiplier,
      :infant_price_multiplier,
      room_type_ids: [],
      rate_plan_age_bands_attributes: [ :id, :min_age, :max_age, :price_multiplier, :label, :position, :_destroy ]
    )
  end

  def authorize!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
  end
end
