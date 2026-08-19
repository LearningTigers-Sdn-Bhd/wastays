# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module AgentLoop
      # One guest message, one model, the tools it may use.
      #
      # This replaces classify-then-route: the model picks the tool instead of
      # filling in a fifteen-slot schema that Ruby then had to interpret,
      # overrule and re-derive. What runs underneath is unchanged -- the same
      # orchestrators, the same booking ladder, the same message builders.
      class RunTurn
        class HopLimitExceeded < StandardError; end

        # RubyLLM's own tool loop has no ceiling: handle_tool_calls recurses
        # into complete until the model stops asking. A concierge turn that
        # needs five tools has misunderstood the guest, and an uncapped loop is
        # an uncapped bill.
        MAX_HOPS = 4
        LLM_TIMEOUT = 30

        TOOL_CLASSES = [
          Tools::Llm::AnswerHotelQuestionTool,
          Tools::Llm::GetNearbyAttractionsTool,
          Tools::Llm::GetRoomTypeDetailsTool,
          Tools::Llm::GetBookingContextTool,
          Tools::Llm::AdvanceBookingTool
          # GenerateBookingUrlTool is deliberately absent. The only way to a
          # payable quote is Booking::CompletionHandler, which is only reached
          # when Postgres says a confirmation was the open question.
        ].freeze

        def initialize(hotel:, prospect:, phone:, conversation_state:, message:)
          @context = TurnContext.new(
            hotel: hotel, prospect: prospect, phone: phone,
            conversation_state: conversation_state, message: message
          )
          @recorder = ToolRecorder.new
        end

        def call
          response = Timeout.timeout(LLM_TIMEOUT) { run }
          recorder.outcome || outcome_from_prose(response)
        rescue Timeout::Error, RubyLLM::Error, HopLimitExceeded, JSON::ParserError => e
          Rails.logger.warn("AiConcierge::AgentLoop degraded: #{e.class}: #{e.message}")
          # A turn that failed halfway still did whatever the tool it already
          # ran did, and that work is the guest's answer. Blast radius is one
          # turn, one guest, one sentence.
          recorder.outcome || Outcome.fallback(conversation_state: context.conversation_state)
        end

        def tools
          @tools ||= TOOL_CLASSES.map { |klass| klass.new(context: context, recorder: recorder) }
        end

        private

        attr_reader :context, :recorder

        def run
          return RunWithoutTools.new(context: context, tools: tools).call unless native_tool_calling?

          BuildChat.new(context: context, tools: tools, recorder: recorder, max_hops: MAX_HOPS).call.ask(context.message)
        end

        def native_tool_calling? = context.hotel.ai_concierge_tool_calling_supported?

        # The model answered without reaching for a tool: a greeting, or a
        # question back. MessengerAgent already renders a bare message when it
        # has no reply type to dispatch on, which is how greetings survive
        # without a decision branch of their own.
        def outcome_from_prose(response)
          content = response.respond_to?(:content) ? response.content : response

          Outcome.fallback(conversation_state: context.conversation_state, message: content.to_s.strip.presence)
        end
      end
    end
  end
end
