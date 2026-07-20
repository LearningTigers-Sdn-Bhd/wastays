# frozen_string_literal: true

module StayView
  class CalculateCounts
    def self.call(room_groups:, room_card_presentations:, reference_date:)
      rows = room_groups.flat_map(&:rooms)
      states = ROOM_CARD_STATES.index_with { 0 }

      rows.each do |room|
        state = room_card_presentations.fetch(room.key).state
        states[state] = states.fetch(state) + 1
      end

      StatusCounts.new(
        reference_date:,
        room_states: states.merge(
          all: rows.size,
          dirty: rows.count { |room| room.current_physical_status == :dirty }
        )
      )
    end
  end
end
