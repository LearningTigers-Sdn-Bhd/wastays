# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module Core
      # Reads a bare yes or no, so the control handler no longer needs a model
      # to run.
      #
      # ConversationControlPolicy is regex over the message for everything
      # except one question: when the hotel has asked "shall we end here?", did
      # the guest say yes. That is a binary a language model is overqualified
      # for, and asking one first meant every goodbye cost a round-trip.
      class ConfirmationReader
        YES = /\A(?:yes|yeah|yep|yup|sure|ok|okay|correct|confirm|please do)\z/
        NO  = /\A(?:no|nope|nah|not really|don'?t|do not)\z/

        def initialize(message:)
          @normalized = message.to_s.downcase.gsub(/[^a-z0-9' ]+/, " ").squish
        end

        def as_interpretation
          return { "intent" => "confirmation", "slots" => { "confirmation" => "yes" } } if normalized.match?(YES)
          return { "intent" => "confirmation", "slots" => { "confirmation" => "no" } } if normalized.match?(NO)

          { "intent" => nil, "slots" => {} }
        end

        private

        attr_reader :normalized
      end
    end
  end
end
