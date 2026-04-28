class Public::HotelsController < ApplicationController
  skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

  def index
    @availability_service = BookingEngine::AvailabilityService.new(params)
    @hotels = @availability_service.find_available_hotels
  end

  def show
    @hotel = Hotel.find(params[:id])
    # Ensure only active hotels are viewable
    unless @hotel.active?
      redirect_to hotels_path, alert: "Hotel not found"
      return
    end

    @check_in = parse_date(params[:check_in])
    @check_out = parse_date(params[:check_out])
    @adults = (params[:adults].presence || 2).to_i
    @children = (params[:children].presence || 0).to_i
    @room_count = (params[:room_count].presence || params[:rooms].presence || 1).to_i
    @search_ready = @check_in.present? && @check_out.present? && @check_out > @check_in
    @show_stay_modal = params[:edit_search].present? || !@search_ready

    if @search_ready
      @availability_service = BookingEngine::AvailabilityService.new(
        params.to_unsafe_h.merge(room_count: @room_count)
      )
      @room_types = @availability_service.available_rooms_for_hotel(@hotel)
    else
      @availability_service = nil
      @room_types = @hotel.room_types
    end
  end

  private

  def parse_date(value)
    return value if value.is_a?(Date)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
