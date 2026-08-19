# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module AgentLoop
      class BuildChat
        # Answering a guest is not a creative task. The same question should
        # reach the same tool every time.
        TEMPERATURE = 0

        def initialize(context:, tools:, recorder:, max_hops:)
          @context = context
          @tools = tools
          @recorder = recorder
          @max_hops = max_hops
        end

        def call
          chat = Providers::RubyLlmClient.new(hotel: context.hotel).chat
          chat.with_instructions(BuildInstructions.new(context: context).call)
          # `calls: :one` disables parallel tool calls, so a single response
          # cannot contain two advance_booking calls.
          chat.with_tools(*tools, calls: :one)
          chat.with_temperature(TEMPERATURE)

          cap_hops(chat)
          chat
        end

        private

        attr_reader :context, :tools, :recorder, :max_hops

        def cap_hops(chat)
          chat.before_tool_call { raise RunTurn::HopLimitExceeded if recorder.hops >= max_hops }
          chat.after_tool_result { recorder.count_hop! }
        end
      end
    end
  end
end
