# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module Core
      # Which intents are the guest asking something rather than booking
      # something.
      #
      # `RevisionPolicy` and `SelectionHandler` each carried their own copy of
      # this list -- the same five strings, word for word, in two classes that
      # do not otherwise know about each other. A sixth information intent
      # would have reached one of them.
      module Intents
        INFORMATIONAL = %w[
          hotel_policy
          hotel_information
          nearby_attractions
          room_information
          booking_context
        ].freeze

        def self.informational?(intent) = INFORMATIONAL.include?(intent.to_s)
      end
    end
  end
end
