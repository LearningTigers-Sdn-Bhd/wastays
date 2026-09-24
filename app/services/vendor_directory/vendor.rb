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
    :offers,
    :photo_url,
    :dietary_tags,
    :reviews
  ) do
    def to_param = id

    def offers? = offers.any?

    def dietary_tags? = dietary_tags.any?

    def reviews? = reviews.any?

    def review_count = reviews.size

    def average_rating
      return if reviews.empty?

      (reviews.sum(&:rating_i).to_f / reviews.size).round(1)
    end

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

    def open_now?(time: Time.current.in_time_zone(VendorDirectory::ZONE))
      hours.any? { |slot| slot.open_at?(time) }
    end

    # The soonest moment any hours slot opens after `time`, across every day
    # of the week the vendor keeps -- nil only when there are no hours at all,
    # or every one of them is marked permanently closed.
    def next_open_at(time: Time.current.in_time_zone(VendorDirectory::ZONE))
      hours.filter_map { |slot| slot.next_open_after(time) }.min
    end

    # When the *current* window closes -- nil while the vendor is closed,
    # since there is nothing counting down.
    def closes_at(time: Time.current.in_time_zone(VendorDirectory::ZONE))
      hours.filter_map { |slot| slot.closes_at_for(time) }.min
    end

    # Same idea as an offer's own "Ending soon": a guest walking over needs
    # to know the door is about to shut, not just that it currently isn't.
    def closing_soon?(time: Time.current.in_time_zone(VendorDirectory::ZONE), within: 45.minutes)
      at = closes_at(time: time)
      at.present? && at <= time + within
    end
  end
end
