module AiConciergeV3
  module Orchestration
    module HotelKnowledge
      class DiagnosticRecorder
        def initialize(hotel:, message:, interpretation:, conversation_state:, result:)
          @hotel = hotel
          @message = message.to_s
          @interpretation = interpretation
          @conversation_state = conversation_state
          @result = result
        end

        def call
          HotelKnowledges::DiagnosticRecorder.new(
            hotel: hotel,
            question: message,
            intent: interpretation["intent"],
            topic: interpretation["topic"],
            tool_result: result,
            prospect: conversation_state&.prospect
          ).call
        end

        private

        attr_reader :hotel, :message, :interpretation, :conversation_state, :result
      end
    end
  end
end
