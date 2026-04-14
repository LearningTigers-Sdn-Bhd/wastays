class StaticPagesController < ApplicationController
  def home
    @availability_service = BookingEngine::AvailabilityService.new(params)
    @featured_stays = @availability_service.find_available_hotels.first(3).filter_map do |hotel|
      room_type = @availability_service.available_rooms_for_hotel(hotel).first
      [ hotel, room_type ] if room_type
    end
  end

  def for_hotels
  end

  def explore
    @availability_service = BookingEngine::AvailabilityService.new(params)
    @featured_stays = @availability_service.find_available_hotels.first(6).filter_map do |hotel|
      room_type = @availability_service.available_rooms_for_hotel(hotel).first
      [ hotel, room_type ] if room_type
    end
  end
end
