class Api::V1::HotelsController < Api::V1::BaseController
  def index
    hotels = hotel_scope.where(status: "live")
    hotels = hotels.where("city ILIKE ?", "%#{params[:city]}%") if params[:city].present?

    render json: hotels.as_json(only: [ :id, :name, :city, :country, :star_rating ])
  end

  def show
    hotel = find_hotel_in_scope!(params[:id])
    return unless hotel

    render json: hotel.as_json(include: {
      room_types: { only: [ :id, :name, :base_price, :max_adults, :max_children ] }
    })
  end

  def availability
    hotel = find_hotel_in_scope!(params[:id])
    return unless hotel

    availability_service = BookingEngine::AvailabilityService.new(
      check_in: params[:check_in],
      check_out: params[:check_out],
      adults: params[:adults],
      children: params[:children],
      room_count: params[:room_count]
    )

    available_rooms = availability_service.available_rooms_for_hotel(hotel)

    response_data = available_rooms.map do |room_type|
      {
        room_type_id: room_type.id,
        name: room_type.name,
        total_price: availability_service.calculate_total_price(room_type),
        currency: room_type.room_rates.first&.currency || "MYR",
        max_adults: room_type.max_adults,
        max_children: room_type.max_children
      }
    end

    render json: {
      hotel_id: hotel.id,
      hotel_name: hotel.name,
      check_in: params[:check_in],
      check_out: params[:check_out],
      available_rooms: response_data
    }
  end

  private

  def find_hotel_in_scope!(identifier)
    hotel = hotel_scope.where(slug: identifier.to_s).first || hotel_scope.find_by(id: identifier)
    return hotel if hotel

    render json: { error: "Forbidden: You do not have access to this hotel" }, status: :forbidden
    nil
  end
end
