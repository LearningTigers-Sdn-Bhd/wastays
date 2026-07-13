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
    attrs = rate_plan_params
    room_type_pricing = attrs.delete(:room_type_pricing) || {}

    @rate_plan = current_hotel.rate_plans.build(attrs)
    @rate_plan.currency = current_hotel.default_currency || "MYR"

    saved = false
    ActiveRecord::Base.transaction do
      saved = @rate_plan.save
      saved = sync_room_type_pricing!(@rate_plan, room_type_pricing) if saved
      raise ActiveRecord::Rollback unless saved
    end

    if saved
      redirect_to hotel_rates_settings_path(current_hotel), notice: "Rate plan '#{@rate_plan.name}' created successfully."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    attrs = rate_plan_params
    room_type_pricing = attrs.delete(:room_type_pricing) || {}

    saved = false
    ActiveRecord::Base.transaction do
      saved = @rate_plan.update(attrs)
      saved = sync_room_type_pricing!(@rate_plan, room_type_pricing) if saved
      raise ActiveRecord::Rollback unless saved
    end

    if saved
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
      rate_plan_age_bands_attributes: [ :id, :min_age, :max_age, :price_multiplier, :label, :position, :_destroy ],
      room_type_pricing: {}
    )
  end

  # Syncs which room types this rate plan applies to, and each room type's
  # pricing_mode/pricing_value, from the per-room-type rows submitted by the
  # form. Returns false (adding an error onto rate_plan) if any row fails to
  # save, so the caller can roll back the whole create/update.
  def sync_room_type_pricing!(rate_plan, room_type_pricing)
    room_type_pricing.each do |room_type_id, attrs|
      room_type = current_hotel.room_types.find_by(id: room_type_id)
      next unless room_type

      rtrp = rate_plan.room_type_rate_plans.find_or_initialize_by(room_type_id: room_type.id)
      enabled = ActiveModel::Type::Boolean.new.cast(attrs[:enabled])

      if enabled
        rtrp.pricing_mode = attrs[:pricing_mode].presence || "fixed"
        rtrp.pricing_value = attrs[:pricing_value].presence

        unless rtrp.save
          rate_plan.errors.add(:base, "#{room_type.name}: #{rtrp.errors.full_messages.to_sentence}")
          return false
        end
      elsif rtrp.persisted?
        rtrp.destroy
      end
    end

    true
  end

  def authorize!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_hotel_profile", hotel: current_hotel)
  end
end
