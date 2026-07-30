# frozen_string_literal: true

module Boats
  # Turns the two submitted time-of-day selections into the two datetime columns
  # a booking guest stores, pairing each with the stay date it belongs to.
  #
  # Returns {} when the property has boat information switched off, or when the
  # form did not submit the fields at all — an absent field means "not
  # submitted" and must never clear a stored time. A submitted-but-blank field
  # does clear it.
  class ResolveTimes
    FIELDS = {
      boat_in_at: { select: :boat_in_time, date: :check_in },
      boat_out_at: { select: :boat_out_time, date: :check_out }
    }.freeze

    def self.call(...) = new(...).call

    def initialize(hotel:, check_in:, check_out:, params:)
      @hotel = hotel
      @dates = { check_in: check_in, check_out: check_out }
      @params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
      @params = @params.symbolize_keys
    end

    def call
      return {} unless @hotel.allow_boat_information?

      FIELDS.each_with_object({}) do |(column, field), attributes|
        next unless @params.key?(field[:select])

        attributes[column] = Schedule.timestamp(
          hotel: @hotel,
          date: @dates[field[:date]],
          time: @params[field[:select]].to_s
        )
      end
    end
  end
end
