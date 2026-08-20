# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module AgentLoop
      # The side channel between a tool and the turn.
      #
      # A tool hands the model a short digest and hands the *domain result* --
      # the reply, the state patch, the retrieved chunks -- to this object.
      # Nothing that matters travels back through the model's context, so a
      # long conversation cannot lose a booking to a trimmed window, and the
      # model cannot rewrite a price on its way past.
      class ToolRecorder
        def initialize
          @hops = 0
          @booking_advanced = false
        end

        attr_reader :hops, :outcome

        def count_hop! = @hops += 1

        def record(domain_result, conversation_state:)
          @outcome = Outcome.new(conversation_state: conversation_state, domain_result: domain_result)
        end

        def recorded? = !@outcome.nil?

        # RubyLLM executes every tool call in a response before it notices the
        # halt, so a provider that ignores `calls: :one` could otherwise run the
        # booking twice in a single turn. This flag, not the halt, is what makes
        # a duplicate quote structurally impossible.
        def booking_advanced? = @booking_advanced
        def mark_booking_advanced! = @booking_advanced = true
      end
    end
  end
end
