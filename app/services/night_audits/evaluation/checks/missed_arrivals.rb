# frozen_string_literal: true

module NightAudits
  module Evaluation
    module Checks
      class MissedArrivals
        REASON = "Arrival requires check-in or no-show resolution before night audit"

        def initialize(context:, serializer: SerializeItems.new)
          @context = context
          @serializer = serializer
        end

        def call
          stays = OverdueGuestStays.new(context: @context)
          { "missed_arrival_not_resolved" => @serializer.bookings(stays.missed_arrivals, REASON) }
        end
      end
    end
  end
end
