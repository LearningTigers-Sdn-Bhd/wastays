# frozen_string_literal: true

require "ruby_llm"

module AiConcierge
  module Tools
    module Llm
      # The model-facing face of a tool the concierge already had.
      #
      # These adapters change who decides which tool runs. They do not change
      # what a tool does: each one hands the turn to the same orchestrator the
      # classify-then-route pipeline used, so the booking ladder, the knowledge
      # short-circuits and the state writes are all the code that was already
      # in production.
      #
      # `Function`, not `Tool`, because three of these used to have exactly the
      # name of the domain tool they call -- `GetRoomTypeDetailsTool` was both
      # this and `Tools::RoomInformation::GetRoomTypeDetailsTool` -- so a
      # backtrace or a grep landed on the wrong one half the time. The suffix
      # the model sees is unchanged; `#name` strips this one instead.
      class BaseFunction < RubyLLM::Tool
        def initialize(context:, recorder:)
          @context = context
          @recorder = recorder
        end

        # RubyLLM derives a tool's name from its full class name, which here
        # would produce "ai_concierge--tools--llm--advance_booking". The model
        # sees this string and has to be able to say it back.
        def name = self.class.name.demodulize.underscore.delete_suffix("_function")

        private

        attr_reader :context, :recorder

        def hotel = context.hotel

        # The domain result goes to the recorder; the model gets a digest.
        #
        # Retrieved chunks, reply text and slot payloads deliberately do not
        # travel back through the context window: a model that can see the
        # reply can rewrite it, and a model that can see a price can invent a
        # different one.
        def record(domain_result, digest: {})
          recorder.record(domain_result, conversation_state: context.conversation_state)
          digest
        end

        # A price question reached an information tool. Rather than answer it
        # badly -- "I couldn't match that room type", to a guest who was ready
        # to book -- the tool hands the turn to the booking machine, which is
        # what the question was always for.
        #
        # Deterministic on purpose. The tool descriptions already say this, and
        # a good model already obeys them, but this is the one misroute the
        # business cannot afford to leave to persuasion.
        def rate_question? = Orchestration::Core::RateQuestion.new(message: context.message).call

        def advance_booking_instead
          AdvanceBookingFunction.new(context: context, recorder: recorder).execute
        end
      end
    end
  end
end
