# frozen_string_literal: true

class HotelPortal::RatePlanRoomPricingsController < HotelPortal::BaseController
  include RatePlanEditorLoading

  before_action :authorize_rate_plan_editor!
  before_action :set_rate_plan
  before_action :set_room_type
  before_action :require_attached_room_type!, only: %i[edit update]

  def edit
    load_rate_plan_editor(room_type_id: @room_type.id)
    render "hotel_portal/rate_plans/edit", layout: false
  end

  def update
    @room_pricing = HotelPortal::RatePlanRoomPricing.from_h(
      room_pricing_params,
      room_type: @room_type,
      sells_per_person: current_hotel.sells_per_person?
    )

    result = with_batched_ari_sync do
      RatePlans::SaveRoomPricing.call(rate_plan: @rate_plan, room_type: @room_type, pricing: @room_pricing)
    end

    if result.success?
      ChannelManagers::SyncRatePlanAri.call(rate_plan: @rate_plan, room_type_ids: [ @room_type.id ])
      render_editor_success("#{@room_type.name} pricing saved.", room_type_id: @room_type.id)
    else
      render_editor_errors(room_type_id: @room_type.id)
    end
  end

  def destroy
    result = RatePlans::RemoveRoomType.call(rate_plan: @rate_plan, room_type: @room_type)
    if return_to_inventory?
      message = result.success? ? "#{@rate_plan.name} detached from #{@room_type.name}." : result.error
      return redirect_to hotel_room_types_path(current_hotel), status: :see_other,
        notice: (message if result.success?), alert: (message unless result.success?)
    end

    if result.success?
      next_room_id = @rate_plan.room_type_rate_plans.order(:id).pick(:room_type_id)
      render_editor_success("#{@room_type.name} removed from this rate plan.", room_type_id: next_room_id)
    else
      @rate_plan.errors.add(:base, result.error)
      render_editor_errors(room_type_id: @room_type.id)
    end
  end

  private

  def set_rate_plan
    @rate_plan = current_hotel.rate_plans.find(params[:rate_plan_id])
  end

  def set_room_type
    @room_type = current_hotel.room_types.find(params[:room_type_id])
  end

  def require_attached_room_type!
    return if @rate_plan.room_type_rate_plans.exists?(room_type: @room_type)

    raise ActiveRecord::RecordNotFound
  end

  def room_pricing_params
    params.require(:room_pricing).permit(
      :rate_mode,
      :default_rate,
      :derive_mode,
      :derive_value,
      :primary_occupancy,
      :increase_by,
      :increase_unit,
      :decrease_by,
      :decrease_unit,
      prices: {}
    )
  end

  def return_to_inventory?
    params[:return_to].to_s == hotel_room_types_path(current_hotel)
  end
end
