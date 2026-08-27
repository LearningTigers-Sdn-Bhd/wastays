# frozen_string_literal: true

module HotelPortal::RoomTypesHelper
  def room_type_amenities_json(room_type)
    (room_type.amenities || []).to_json
  end

  def all_room_amenities_json
    Hotel::ROOM_AMENITIES.to_json
  end

  def categorized_room_amenities
    Hotel::CATEGORIZED_ROOM_AMENITIES
  end
end
