# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module AgentLoop
      # The whole prompt.
      #
      # It is short because the tools are where the knowledge lives now: each
      # one describes when it is for, so the model reads the menu rather than a
      # decision tree. The 200 lines this replaces existed to describe a choice
      # the model was never allowed to make.
      class BuildInstructions
        def initialize(context:)
          @context = context
        end

        def call
          <<~INSTRUCTIONS.strip
            You are the concierge for #{context.hotel.name}. Today is #{Date.current.iso8601}.

            Pick the tool that fits what the guest wants. Every tool writes the
            reply itself, so once you have called one you are finished -- do not
            write an answer of your own, do not summarise what the tool did, and
            do not call a second tool to check the first.

            Only greet or ask for a clarification in your own words when no tool
            fits at all. A guest who wants to book, reserve, check availability
            or price a stay is never that case: call advance_booking even when
            they have given you nothing to extract yet, and let the booking
            system ask the first question. Never ask a guest which room type
            they want -- they choose one from a list you have shown them.

            Never state a price, a date, a room's availability or a policy from
            your own knowledge. You do not have that information; the tools do.
            #{room_types}#{knowledge_languages}#{open_question}
          INSTRUCTIONS
        end

        private

        attr_reader :context

        # Search matches words, and the hotel chose which language to file each
        # document under. A guest asking in one language about an answer written
        # in another needs the question looked up in both, and the model is the
        # only part of this that can say the same thing twice.
        def knowledge_languages
          languages = context.knowledge_languages
          return "" if languages.empty?

          "\nThe hotel's documents are written in: #{languages.join(', ')}. " \
            "When you look something up, give search_terms in each of those languages.\n"
        end

        def room_types
          names = context.room_type_names
          return "" if names.empty?

          "\nThe hotel's room types are: #{names.join(', ')}.\n"
        end

        # The model is told what was asked so it can read the answer, and never
        # told to decide what to ask next.
        def open_question
          return "" if context.pending_question.blank?

          "\nThe hotel has already asked this guest about their booking " \
            "(#{context.pending_question.tr('_', ' ')}), so this message is most " \
            "likely their answer to it.\n"
        end
      end
    end
  end
end
