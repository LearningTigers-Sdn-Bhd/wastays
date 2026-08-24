# frozen_string_literal: true

class HotelNearbyAttraction < ApplicationRecord
  belongs_to :hotel
  belongs_to :attraction

  validates :attraction_id, uniqueness: { scope: :hotel_id }

  delegate :name, :address, :city, :country, :google_maps_url, to: :attraction

  def guest_description
    description.presence || attraction.display_description
  end

  def distance_from(other_hotel = hotel)
    return if attraction.latitude.blank? || attraction.longitude.blank?
    return if other_hotel.latitude.blank? || other_hotel.longitude.blank?

    Attractions::Distance.kilometers(
      other_hotel.latitude,
      other_hotel.longitude,
      attraction.latitude,
      attraction.longitude
    )
  end
end
