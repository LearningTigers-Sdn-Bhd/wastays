# frozen_string_literal: true

class HotelPortal::Bookings::PricesController < HotelPortal::BaseController
  before_action :authorize_view_bookings!

  def show
    if params[:check_in].blank? || params[:check_out].blank? || params[:room_type_id].blank?
      return render json: { total_amount: 0 }
    end

    room_type = current_hotel.room_types.find(params[:room_type_id])
    rate_plan, rate_tier = parse_rate_selection(room_type, params[:rate_plan_id])

    snapshot = Bookings::BuildFinancialSnapshot.new(
      hotel: current_hotel,
      room_type: room_type,
      rate_plan: rate_plan,
      rate_tier: rate_tier,
      check_in: Date.parse(params[:check_in]),
      check_out: Date.parse(params[:check_out]),
      guest_country: params[:guest_country].presence || current_hotel.country,
      corporate_rate: params[:corporate_rate] == "true"
    ).call
    total = snapshot.room_total + snapshot.tax_total

    render json: { total_amount: total }
  rescue ArgumentError => e
    render json: { error: e.message, total_amount: 0 }, status: :unprocessable_content
  end

  private

  def parse_rate_selection(room_type, rate_plan_id)
    return [ nil, :standard ] if rate_plan_id.blank?

    if rate_plan_id.to_s.start_with?("tier_")
      parts = rate_plan_id.to_s.split("_")
      kind = parts[1] == "walk" ? :walk_in : parts[1].to_sym
      real_plan_id = parts.last
      plan = room_type.rate_plans.find_by(id: real_plan_id)
      [ plan, kind ]
    else
      plan = room_type.rate_plans.find_by(id: rate_plan_id)
      [ plan, :standard ]
    end
  end

  def authorize_view_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_bookings", hotel: current_hotel)
  end
end
