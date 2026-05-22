module ConciergeBookingLookup
  private

  def resolve_concierge_booking_from_params(missing_token_message: "Confirmation code is required.",
                                            not_found_message: "Booking not found. Please check your confirmation code.",
                                            fallback_message: "Something went wrong. Please try again.")
    token = params[:confirmation_token].to_s.strip
    if token.blank?
      @error = missing_token_message
      @booking = nil
      render :new, status: :unprocessable_content
      return nil
    end

    lookup = ::Concierge::BookingLookup.new(
      hotel: @hotel,
      confirmation_token: token,
      request_ip: request.remote_ip
    ).call

    return persist_concierge_booking(lookup.booking) if lookup.success?

    @error = concierge_lookup_error_message(
      lookup.error_code,
      not_found_message:,
      fallback_message:
    )
    @booking = nil
    render :new, status: :unprocessable_content
    nil
  end

  def persist_concierge_booking(booking)
    set_concierge_booking_cookie(booking)
    booking
  end

  def concierge_lookup_error_message(code, not_found_message:, fallback_message:)
    case code
    when :not_found then not_found_message
    else fallback_message
    end
  end
end
