# frozen_string_literal: true

module Attractions
  class PublicHotelLinks
    Result = Data.define(:link, :distance_km, :maps_url)

    def self.call(hotel:)
      hotel_coordinates = [ hotel.latitude, hotel.longitude ]

      hotel.hotel_nearby_attractions
        .includes(:attraction)
        .joins(:attraction)
        .where(attractions: { status: %w[approved pending] })
        .map do |link|
          attraction = link.attraction
          distance = if hotel_coordinates.all? && attraction.latitude.present? && attraction.longitude.present?
            Distance.kilometers(*hotel_coordinates, attraction.latitude, attraction.longitude)
          end
          maps_url = attraction.google_maps_url.presence ||
            "https://www.google.com/maps/search/?api=1&query=#{ERB::Util.url_encode([ attraction.name, attraction.city, attraction.country ].compact_blank.join(", "))}"

          Result.new(link: link, distance_km: distance, maps_url: maps_url)
        end
        .sort_by { |row| [ row.distance_km.nil? ? 1 : 0, row.distance_km || 0, row.link.attraction.name.downcase, row.link.id ] }
    end
  end
end
