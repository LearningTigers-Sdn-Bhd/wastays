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
          Tools::Llm::AnswerHotelQuestionFunction,
          Tools::Llm::GetNearbyAttractionsFunction,
          Tools::Llm::GetRoomTypeDetailsFunction,
          Tools::Llm::GetBookingContextFunction,
          Tools::Llm::AdvanceBookingFunction
          # GenerateBookingUrlTool has no function here on purpose. The only way to a
          # payable quote is Booking::CompletionHandler, which is only reached
          # when Postgres says a confirmation was the open question.
        ].freeze

        def initialize(hotel:, prospect:, phone:, conversation_state:, message:,
                       thread_language: nil, conversation: nil)
          @context = TurnContext.new(
            hotel: hotel, prospect: prospect, phone: phone,
            conversation_state: conversation_state, message: message,
            thread_language: thread_language, conversation: conversation
          )
          @recorder = ToolRecorder.new
        end

        def call
          if (clarification = resolve_knowledge_clarification)
            return Outcome.new(conversation_state: context.conversation_state, domain_result: clarification)
          end

          response = Timeout.timeout(LLM_TIMEOUT) { run }
          recorder.outcome || booking_backstop || outcome_from_prose(response)
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

        def resolve_knowledge_clarification
          HotelKnowledge::ClarificationResolver.new(context: context).call
        end

        def run
          response = BuildChat.new(context: context, tools: tools, recorder: recorder, max_hops: MAX_HOPS)
            .call.ask(context.message)
          Providers::UsageLog.call(response, hotel: context.hotel, stage: :loop)
          response
        end

        # A guest who wants to book gets the booking ladder, not the model's
        # own idea of what to ask. "Can I make a booking" states no slots, so a
        # model hunting for something to extract can decide no tool fits and
        # improvise a question -- and the question it improvises asks for a
        # room type the guest cannot yet know.
        #
        # Empty slots are the point: PrepareTurn merges nothing, ActionResolver
        # reads a branch with no dates and opens with :ask_booking_timing.
        # The open question is the language-neutral half. Reading the message
        # for booking words only works in English, but a hotel that has asked
        # the guest something and got prose back is mid-ladder whatever
        # language the thread is in -- and re-asking is always better than
        # letting the model answer for the booking system.
        def booking_backstop
          return unless context.pending_question.present? || booking_words?

          advance_booking_tool&.execute(slots: {}, signals: {})
          recorder.outcome
        end

        def booking_words? = Matching::BookingIntentMatcher.new(message: context.message).booking?

        def advance_booking_tool
          tools.find { |tool| tool.is_a?(Tools::Llm::AdvanceBookingFunction) }
        end

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
