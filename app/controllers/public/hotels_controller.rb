class Public::HotelsController < ApplicationController
  skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

  def index
    @availability_service = BookingEngine::AvailabilityService.new(params)
    @hotels = @availability_service.find_available_hotels
  end

  def show
    @hotel = Hotel.find(params[:id])
    # Ensure only active hotels are viewable
    redirect_to hotels_path, alert: "Hotel not found" unless @hotel.active?

    @availability_service = BookingEngine::AvailabilityService.new(params)
    @room_types = @availability_service.available_rooms_for_hotel(@hotel)
  end
end
