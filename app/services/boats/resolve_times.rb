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
    class InvalidSelection < ArgumentError; end
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
      @schedule = Schedule.new(hotel)
    end

    def call
      return {} unless @hotel.allow_boat_information?

      FIELDS.each_with_object({}) do |(column, field), attributes|
        next unless @params.key?(field[:select])

        selection = @params[field[:select]].to_s
        direction = column.to_s.delete_suffix("_at")
        type, time = resolve(selection, direction)
        attributes["#{direction}_type".to_sym] = type
        attributes[column] = Schedule.timestamp(
          hotel: @hotel,
          date: @dates[field[:date]],
          time: time
        )
      end
    end

    private

    def resolve(selection, direction)
      return [ nil, nil ] if selection.blank?

      label = direction.tr("_", "-")
      if selection.in?(BookingGuest::CUSTOM_BOAT_TYPES)
        time = @params["#{direction}_custom_time".to_sym].to_s
        if time.blank? && selection == "charter"
          raise InvalidSelection, "Enter a #{label} time for Charter Boat."
        end
        if time.present? && !Schedule.valid_time?(time)
          raise InvalidSelection, "Enter a valid #{label} time."
        end
        return [ selection, time ]
      end

      unless Schedule.valid_time?(selection) && @schedule.slot_at(selection, direction)
        raise InvalidSelection, "Choose a #{label} option from the hotel's boat timetable."
      end

      [ "provided", selection ]
    end
  end
end
