# frozen_string_literal: true

module Attractions
  class Suggestions
    Result = Data.define(:attraction, :distance_km)
    DEFAULT_LIMIT = 10
    DEFAULT_RADIUS_KM = 25
    KM_PER_LATITUDE_DEGREE = 111.32

    def self.call(hotel:, limit: DEFAULT_LIMIT, radius_km: DEFAULT_RADIUS_KM)
      new(hotel: hotel, limit: limit, radius_km: radius_km).call
    end

    def initialize(hotel:, limit:, radius_km:)
      @hotel = hotel
      @limit = limit.to_i.clamp(1, DEFAULT_LIMIT)
      @radius_km = radius_km.to_f.clamp(0, DEFAULT_RADIUS_KM)
    end

    def call
      return [] if hotel_coordinates.blank? || @radius_km.zero?

      candidates.filter_map do |attraction|
        distance = Distance.kilometers(*hotel_coordinates, attraction.latitude, attraction.longitude)
        Result.new(attraction: attraction, distance_km: distance) if distance <= @radius_km
      end.sort_by { |row| [ row.distance_km, row.attraction.id ] }.first(@limit)
    end

    private

    def hotel_coordinates
      return @hotel_coordinates if defined?(@hotel_coordinates)

      @hotel_coordinates = if @hotel.latitude.present? && @hotel.longitude.present?
        [ @hotel.latitude, @hotel.longitude ]
      end
    end

    def candidates
      latitude, longitude = hotel_coordinates.map(&:to_f)
      latitude_delta = @radius_km / KM_PER_LATITUDE_DEGREE
      longitude_scale = Math.cos(latitude * Math::PI / 180).abs
      longitude_delta = longitude_scale < 0.001 ? 180 : [ @radius_km / (KM_PER_LATITUDE_DEGREE * longitude_scale), 180 ].min

      Attraction.approved_for_suggestions
        .where(latitude: (latitude - latitude_delta)..(latitude + latitude_delta))
        .where(longitude: (longitude - longitude_delta)..(longitude + longitude_delta))
        .where.not(id: @hotel.hotel_nearby_attractions.select(:attraction_id))
        .order(:id)
    end
  end
end
