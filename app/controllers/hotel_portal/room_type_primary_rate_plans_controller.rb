# frozen_string_literal: true

# Picks the rate plan a room category leads with on the booking site and in
# the travel agent portal. The Standard plan stays the pricing anchor either way.
class HotelPortal::RoomTypePrimaryRatePlansController < HotelPortal::BaseController
  before_action :authorize_primary_plan_editor!

  def update
    room_type = current_hotel.room_types.find(params[:room_type_id])
    rate_plan = current_hotel.rate_plans.find(params.require(:rate_plan_id))

    result = RatePlans::MakePrimary.call(room_type: room_type, rate_plan: rate_plan)
    if result.success?
      redirect_to hotel_room_types_path(current_hotel), status: :see_other,
        notice: "#{rate_plan.name} is now the primary plan for #{room_type.name}."
    else
      redirect_to hotel_room_types_path(current_hotel), status: :see_other, alert: result.error
    end
  end

  private

  # Same gate as the rest of Room Inventory.
  def authorize_primary_plan_editor!
    authorize current_hotel, :update?, policy_class: HotelPolicy
  end
end
