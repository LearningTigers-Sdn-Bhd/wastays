# frozen_string_literal: true

class HotelPortal::Bookings::PricesController < HotelPortal::BaseController
  before_action :authorize_view_bookings!

  def show
    if params[:check_in].blank? || params[:check_out].blank? || params[:room_type_id].blank?
      return render json: { total_amount: 0 }
    end

    room_type = current_hotel.room_types.find(params[:room_type_id])
    rate_plan = parse_rate_selection(room_type, params[:rate_plan_id])

    snapshot = Bookings::BuildFinancialSnapshot.new(
      hotel: current_hotel,
      room_type: room_type,
      rate_plan: rate_plan,
      check_in: Date.parse(params[:check_in]),
      check_out: Date.parse(params[:check_out]),
      guest_country: params[:guest_country].presence || current_hotel.country,
      adults: params[:adults].presence,
      children: params[:children].presence
    ).call
    tourism_tax_total = Booking.tourism_tax_total_for(snapshot.tax_lines)
    payable_tax_total = Booking.non_tourism_tax_total_for(snapshot.tax_lines)
    total = snapshot.room_total + payable_tax_total

    render json: {
      total_amount: total,
      room_total: snapshot.room_total,
      tax_total: payable_tax_total,
      tourism_tax_total: tourism_tax_total,
      tax_lines: snapshot.tax_lines,
      nightly_rate_snapshot: snapshot.nightly_rate_snapshot
    }
  rescue ArgumentError => e
    render json: { error: e.message, total_amount: 0 }, status: :unprocessable_content
  end

  def payment_quote
    PaymentMethods::EnsureDefaults.call(current_hotel)
    purpose = params[:purpose].to_s == "direct" ? :direct : :guest_advance
    result = PaymentMethods::Quote.call(
      hotel: current_hotel,
      payment_method_id: params[:hotel_payment_method_id],
      base_amount: params[:base_amount],
      purpose:
    )
    return render json: { error: result.error }, status: :unprocessable_content unless result.success?

    render json: {
      base_amount: result.base_amount.to_s("F"),
      surcharge_amount: result.surcharge_amount.to_s("F"),
      surcharge_tax_total: result.surcharge_tax_total.to_s("F"),
      collected_total: result.collected_total.to_s("F")
    }
  end

  private

  def parse_rate_selection(room_type, rate_plan_id)
    return room_type.standard_rate_plan if rate_plan_id.blank?

    selection = Bookings::RateSelection.resolve(room_type:, value: rate_plan_id)
    selection.rate_plan || raise(ArgumentError, "Selected rate is no longer available.")
  end

  def authorize_view_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_bookings", hotel: current_hotel)
  end
end
