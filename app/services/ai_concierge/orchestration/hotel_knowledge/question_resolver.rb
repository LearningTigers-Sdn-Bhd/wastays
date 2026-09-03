# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module HotelKnowledge
      # Resolves one hotel question without changing conversation state or adding a sales action.
      class QuestionResolver
        Result = Struct.new(:tool_result, :reply, :answer, keyword_init: true)

        def initialize(hotel:, message:, interpretation:, language:, previous_reply: nil, max_list_facts: nil, localize: true)
          @hotel = hotel
          @message = message.to_s
          @interpretation = interpretation
          @language = language.to_s.presence || Conversation::DEFAULT_LANGUAGE
          @previous_reply = previous_reply.to_s
          @max_list_facts = max_list_facts
          @localize = localize
        end

        def call
          tool_result = ToolRouter.new(hotel: hotel, message: message, interpretation: interpretation).call
          reply = ReplyFactory.new(intent: interpretation["intent"], result: tool_result[:result]).call
          reply = limited(reply)
          answer = factual_message(reply)
          answer = Localizer.new(hotel: hotel, reply: answer, language: language).call if localize

          Result.new(tool_result: tool_result, reply: reply, answer: answer)
        end

        private

        attr_reader :hotel, :message, :interpretation, :language, :previous_reply, :max_list_facts, :localize

        def limited(reply)
          return reply if max_list_facts.blank? || reply.shape != "list"

          Reply.from_h(reply.to_h.merge("facts" => reply.facts.first(max_list_facts).map(&:to_h)))
        end

        def factual_message(reply)
          return HotelOverviewComposer.new(hotel: hotel, reply: reply, tone: hotel.ai_concierge_tone).call if hotel_overview?(reply)

          ReplyComposer.new(
            reply: reply,
            tone: hotel.ai_concierge_tone,
            message: message,
            previous_reply: previous_reply
          ).call
        end

        def hotel_overview?(reply)
          interpretation["topic"] == "general_hotel_info" && reply.shape == "list"
        end
      end
    end
  end
end
