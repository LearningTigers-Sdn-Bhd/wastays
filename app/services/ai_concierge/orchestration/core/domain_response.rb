# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module Core
      # What a turn decided, on its way to the persister.
      #
      # This shape used to be a bare Hash built in seven places -- four copies
      # of `booking_response`, two `domain_response`s and one inline literal --
      # and they had already drifted: three of them omitted `flow_status` and
      # `end_reason` entirely, and only `ResponsePersister` reading with `[]`
      # rather than `fetch` kept that from raising. The only contract anywhere
      # was `key?(:slots_payload) && key?(:reply_type)`, which is structural
      # typing on a Hash.
      #
      # A Struct rather than a Data: `[]` and `dig` are how every caller and a
      # hundred-odd specs already read this, and Data has neither.
      DomainResponse = Struct.new(
        :slots_payload,
        :reply_type,
        :active_topic,
        :active_flow,
        :pending_question,
        :action_name,
        :extra_context,
        :flow_status,
        :end_reason,
        :needs_human_support,
        keyword_init: true
      ) do
        # Everything a booking turn always says about itself. The topic, the
        # flow and the action were repeated at every one of the twenty-odd
        # exits of the booking ladder; they are the same three strings each
        # time, so they live here instead.
        BOOKING_FLOW = "booking_search"

        def self.booking(slots_payload:, reply_type:, pending_question:, extra_context: {}, action_name: "request_quote")
          new(
            slots_payload: slots_payload,
            reply_type: reply_type,
            pending_question: pending_question,
            active_topic: BOOKING_FLOW,
            active_flow: BOOKING_FLOW,
            action_name: action_name,
            extra_context: extra_context
          )
        end

        def initialize(extra_context: {}, needs_human_support: false, **rest)
          super(extra_context: extra_context, needs_human_support: needs_human_support, **rest)
        end

        # `Struct` has no `#with` -- only `Data` does -- and the callers that
        # used to reach for `Hash#merge` (the re-ask nudge, the handover flag,
        # the resume's zeroed counter) need a copy with one field changed.
        def with(**changes) = self.class.new(**to_h.merge(changes))
      end
    end
  end
end
