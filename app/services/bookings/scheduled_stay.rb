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

    # The dates a stay is billed for. An overnight stay bills each night; a
    # day-use stay (arrives and leaves on the same date) bills that one date.
    def stay_dates(hotel:, check_in:, check_out:)
      arrival_date = local_date(hotel: hotel, value: check_in)
      departure_date = local_date(hotel: hotel, value: check_out)
      return [] if arrival_date.blank? || departure_date.blank? || departure_date < arrival_date
      return [ arrival_date ] if day_use?(hotel: hotel, check_in: check_in, check_out: check_out)

      (arrival_date...departure_date).to_a
    end

    # Same date in and out, leaving after arriving. Date-only callers carry no
    # time, so they use `billable_dates` and let the rate plan say it is day use.
    def day_use?(hotel:, check_in:, check_out:)
      return false if check_in.blank? || check_out.blank?

      check_in_at = at_hotel_time(hotel: hotel, value: check_in, kind: :check_in)
      check_out_at = at_hotel_time(hotel: hotel, value: check_out, kind: :check_out)
      check_out_at > check_in_at && check_out_at.to_date == check_in_at.to_date
    end

    def billable_dates(arrival_date, departure_date)
      return [ arrival_date ] if arrival_date == departure_date

      (arrival_date...departure_date).to_a
    end
  end
end
