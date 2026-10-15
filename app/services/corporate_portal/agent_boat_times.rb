# frozen_string_literal: true

module CorporatePortal
  # Agents can choose active scheduled boats or record custom transfers.
  # Custom times use the same validation as staff transfers.
  #
  # #params is what Boats::AssignTimes / Boats::ResolveTimes read: only the
  # fields the form actually sent, so an absent field never clears a time the
  # desk already recorded, while a submitted blank ("No boat transfer") does.
  class AgentBoatTimes
    FIELDS = { boat_in_time: :in_times, boat_out_time: :out_times }.freeze
    LABELS = { boat_in_time: "boat-in", boat_out_time: "boat-out" }.freeze

    def initialize(hotel:, params:)
      @schedule = ::Boats::Schedule.new(hotel)
      @hotel = hotel
      @params = params.to_h.symbolize_keys.slice(*FIELDS.keys, :boat_in_custom_time, :boat_out_custom_time).transform_values(&:to_s)
    end

    def params
      @schedule.enabled? ? @params : {}
    end

    def errors
      FIELDS.filter_map do |field, times|
        next unless params.key?(field)

        value = params[field]
        unless value.blank? || value.in?(BookingGuest::CUSTOM_BOAT_TYPES) || @schedule.public_send(times).include?(value)
          next "Choose a #{LABELS.fetch(field)} time from the hotel's boat timetable."
        end

        begin
          custom_field = field.to_s.sub("_time", "_custom_time").to_sym
          ::Boats::ResolveTimes.call(hotel: @hotel, check_in: nil, check_out: nil, params: params.slice(field, custom_field))
          nil
        rescue ::Boats::ResolveTimes::InvalidSelection => e
          e.message
        end
      end
    end
  end
end
