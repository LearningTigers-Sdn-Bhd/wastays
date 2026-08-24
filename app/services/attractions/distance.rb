# frozen_string_literal: true

module Attractions
  class Distance
    EARTH_RADIUS_KM = 6_371.0

    def self.kilometers(latitude_a, longitude_a, latitude_b, longitude_b)
      latitude_a, longitude_a, latitude_b, longitude_b =
        [ latitude_a, longitude_a, latitude_b, longitude_b ].map(&:to_f)
      radians = Math::PI / 180
      latitude_delta = (latitude_b - latitude_a) * radians
      longitude_delta = (longitude_b - longitude_a) * radians
      latitude_a_radians = latitude_a * radians
      latitude_b_radians = latitude_b * radians

      haversine = Math.sin(latitude_delta / 2)**2 +
        Math.cos(latitude_a_radians) * Math.cos(latitude_b_radians) * Math.sin(longitude_delta / 2)**2
      arc = 2 * Math.atan2(Math.sqrt(haversine), Math.sqrt(1 - haversine))

      EARTH_RADIUS_KM * arc
    end
  end
end
