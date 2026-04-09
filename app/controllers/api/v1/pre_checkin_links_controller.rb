class Api::V1::PreCheckinLinksController < Api::V1::BaseController
  def create
    booking = booking_scope.find_by(confirmation_token: params[:booking_token])

    unless booking
      render json: { error: "Booking not found or access denied" }, status: :not_found
      return
    end

    validation_error = validate_booking_context!(booking)
    return if performed? || validation_error

    pre_checkin_result = GuestArrival::StartPreCheckin.new(booking).call

    if pre_checkin_result.success?
      pre_checkin = pre_checkin_result.pre_checkin

      render json: {
        booking_token: booking.confirmation_token,
        guest_name: booking.guest_name,
        hotel_name: booking.hotel.name,
        check_in_date: booking.check_in,
        check_out_date: booking.check_out,
        pre_checkin_url: public_pre_checkin_url(pre_checkin.token)
      }
    else
      render json: { error: pre_checkin_result.message }, status: :unprocessable_content
    end
  end

  private

  def validate_booking_context!(booking)
    if params[:guest_name].present? && params[:guest_name] != booking.guest_name
      render json: { error: "Guest name does not match the booking" }, status: :unprocessable_content
      return true
    end

    if params[:hotel_name].present? && params[:hotel_name] != booking.hotel.name
      render json: { error: "Hotel name does not match the booking" }, status: :unprocessable_content
      return true
    end

    if params[:check_in_date].present? && params[:check_in_date].to_s != booking.check_in.to_date.iso8601
      render json: { error: "Check-in date does not match the booking" }, status: :unprocessable_content
      return true
    end

    if params[:check_out_date].present? && params[:check_out_date].to_s != booking.check_out.to_date.iso8601
      render json: { error: "Check-out date does not match the booking" }, status: :unprocessable_content
      return true
    end

    false
  end

  def public_pre_checkin_url(token)
    "#{request.base_url}/pre-checkin/#{token}"
  end
end
