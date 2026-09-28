# frozen_string_literal: true

module CorporatePortal
  # The boat slots a travel agent picked for a stay. Staff are trusted to post
  # any slot, retired ones included; an agent may only choose one the hotel
  # still runs, and only when the hotel keeps a boat timetable at all.
  #
  # #params is what Boats::AssignTimes / Boats::ResolveTimes read: only the
  # fields the form actually sent, so an absent field never clears a time the
  # desk already recorded, while a submitted blank ("No boat transfer") does.
  class AgentBoatTimes
    FIELDS = { boat_in_time: :in_times, boat_out_time: :out_times }.freeze
    LABELS = { boat_in_time: "boat-in", boat_out_time: "boat-out" }.freeze

    def initialize(hotel:, params:)
      @schedule = ::Boats::Schedule.new(hotel)
      @params = params.to_h.symbolize_keys.slice(*FIELDS.keys).transform_values(&:to_s)
    end

    def params
      @schedule.enabled? ? @params : {}
    end

    def errors
      params.filter_map do |field, value|
        next if value.blank? || @schedule.public_send(FIELDS.fetch(field)).include?(value)

        "Choose a #{LABELS.fetch(field)} time from the hotel's boat timetable."
      end
    end
  end
end
