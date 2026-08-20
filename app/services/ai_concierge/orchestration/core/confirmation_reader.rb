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
      #
      # The booking tool asks the same question of the same words -- a "yes" the
      # model forgot to pass along is still a yes -- so the vocabulary lives
      # here rather than in two places drifting apart.
      class ConfirmationReader
        # Short and additive on purpose, in the languages the hotel is written
        # in. A word missing from here costs the guest the question a second
        # time and can never spend their money by mistake.
        YES = %w[
          yes yeah yep yup ya sure ok okay okey correct confirm confirmed proceed
          ye betul baik boleh setuju
          好 好的 是 是的 可以 确认 確認
        ].freeze
        NO = %w[
          no nope nah dont don't do\ not not\ really cancel
          tak tidak jangan bukan
          不 不要 不用 取消
        ].freeze

        # Words that soften an answer without changing it. Trimmed so "yes
        # please" reads as a yes, while "yes please tell me about the pool"
        # still does not: a sentence that merely contains "yes" is not an
        # answer to a yes/no question, and reading it as one would end
        # conversations people meant to continue.
        POLITENESS = %w[please thanks thank you la lah already then it that].freeze

        def initialize(message:)
          @normalized = message.to_s.downcase.gsub(/[^[:alnum:]'’ ]+/, " ").squish
        end

        def as_interpretation
          return { "intent" => "confirmation", "slots" => { "confirmation" => confirmation } } if confirmation

          { "intent" => nil, "slots" => {} }
        end

        # "yes", "no", or nil when the message is not an answer to a yes/no.
        def confirmation
          return @confirmation if defined?(@confirmation)

          @confirmation = if YES.include?(core_answer)
            "yes"
          elsif NO.include?(core_answer)
            "no"
          end
        end

        private

        attr_reader :normalized

        # What is left once the politeness is taken off. Kept whole rather than
        # tokenised so a two-word answer -- "not really", "do not" -- survives.
        def core_answer
          @core_answer ||= (normalized.split - POLITENESS).join(" ")
        end
      end
    end
  end
end
