# frozen_string_literal: true

module VendorDirectory
  Vendor = Data.define(
    :id,
    :category_slug,
    :name,
    :tagline,
    :accent,
    :price_range,
    :tags,
    :summary,
    :address,
    :phone,
    :distance_km,
    :walking_minutes,
    :hours,
    :google_maps_url,
    :latitude,
    :longitude,
    :offers
  ) do
    def to_param = id

    def offers? = offers.any?

    def offer(id) = offers.find { |offer| offer.id == id }

    def distance_label
      return if distance_km.blank?

      distance_km < 1 ? "#{(distance_km * 1000).round(-1)} m" : "#{format('%.1f', distance_km)} km"
    end

    def offer_count_label
      case offers.size
      when 0 then "No offers right now"
      when 1 then "1 offer"
      else "#{offers.size} offers"
      end
    end
  end
end
