class Public::HotelsController < ApplicationController
  skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

  def index
    @availability_service = BookingEngine::AvailabilityService.new(params)
    @hotels = @availability_service.find_available_hotels
    @display_currency = display_currency_for_request
  end

  def show
    @hotel = Hotel.friendly.find(params[:id])
    # Ensure only active hotels are viewable
    unless @hotel.active?
      redirect_to hotels_path, alert: "Hotel not found"
      return
    end

    # Auto-fetch today and tomorrow if dates are missing
    @check_in = parse_date(params[:check_in]) || Date.current
    @check_out = parse_date(params[:check_out]) || Date.tomorrow

    @adults = (params[:adults].presence || 2).to_i
    @children = (params[:children].presence || 0).to_i
    @room_count = (params[:room_count].presence || params[:rooms].presence || 1).to_i
    @display_currency = display_currency_for_request

    @search_ready = @check_in.present? && @check_out.present? && @check_out > @check_in

    if @search_ready
      @availability_service = BookingEngine::AvailabilityService.new(
        params.to_unsafe_h.merge(
          check_in: @check_in,
          check_out: @check_out,
          room_count: @room_count
        )
      )
      @room_types = @availability_service.available_rooms_for_hotel(@hotel)
    else
      @availability_service = nil
      @room_types = @hotel.room_types
    end

    hotel_sort_order = [ "General", "Services", "Parking", "Safety And Security", "Food And Drink", "Activities", "Outdoors", "Pets" ]

    @categorized_amenities = Amenity.where(slug: @hotel.amenities, amenity_type: :hotel)
                                    .ordered
                                    .group_by(&:category)
                                    .sort_by { |category, _|
                                      hotel_sort_order.index(category) || hotel_sort_order.size
                                    }

    # Decorate for view
    @hotel = Public::HotelPresenter.new(@hotel, view_context)
    @room_types = @room_types.map { |rt| Public::RoomTypePresenter.new(rt, @hotel, @availability_service, view_context) }
  end

  def rate_calendar
    @hotel = Hotel.friendly.find(params[:id])
    return head :not_found unless @hotel.active?

    start_date = parse_date(params[:start_date]) || Date.current
    end_date   = parse_date(params[:end_date])   || (start_date + 90)
    room_count = (params[:room_count].presence || 1).to_i

    result = BookingEngine::RateCalendarService.new(
      hotel: @hotel,
      start_date: start_date,
      end_date: end_date,
      room_count: room_count,
      partner_code: params[:partner_code]
    ).call

    expires_in 5.minutes, public: true
    render json: {
      hotel_id: @hotel.slug,
      currency: result[:currency],
      start_date: start_date.iso8601,
      end_date: end_date.iso8601,
      days: result[:days].map { |d|
        { date: d.date.iso8601, min_price: d.min_price, available: d.available, rooms_left: d.rooms_left }
      }
    }
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  private

  def parse_date(value)
    return value if value.is_a?(Date)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def display_currency_for_request
    DisplayCurrencyResolver.new(params: params, cookies: cookies, request: request).call
  end
end
