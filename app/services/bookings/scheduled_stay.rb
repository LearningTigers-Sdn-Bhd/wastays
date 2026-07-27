# frozen_string_literal: true

module Bookings
  module ScheduledStay
    DEFAULT_CHECK_IN_TIME = "15:00"
    DEFAULT_CHECK_OUT_TIME = "12:00"

    module_function

    def at_hotel_time(hotel:, value:, kind:)
      return if value.blank?
      return value.in_time_zone(hotel.hotel_time_zone) if value.respond_to?(:acts_like_time?) && value.acts_like_time?

      string = value.to_s
      return hotel.hotel_time_zone.parse(string) if string.match?(/\d[T ]\d/)

      date = Date.parse(string)
      hotel.hotel_time_zone.parse("#{date} #{policy_time(hotel, kind)}")
    end

    def policy_time(hotel, kind)
      policy_value = hotel.property_policy&.public_send("#{kind}_time").presence
      policy_value || (kind.to_sym == :check_in ? DEFAULT_CHECK_IN_TIME : DEFAULT_CHECK_OUT_TIME)
    end

    def local_date(hotel:, value:)
      return if value.blank?
      return value.in_time_zone(hotel.hotel_time_zone).to_date if value.respond_to?(:acts_like_time?) && value.acts_like_time?

      value.to_date
    end

    def stay_dates(hotel:, check_in:, check_out:)
      arrival_date = local_date(hotel: hotel, value: check_in)
      departure_date = local_date(hotel: hotel, value: check_out)
      return [] if arrival_date.blank? || departure_date.blank? || departure_date <= arrival_date

      (arrival_date...departure_date).to_a
    end
  end
end
