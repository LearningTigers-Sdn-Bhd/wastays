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
          client = Providers::RubyLlmClient.new(hotel: context.hotel)
          chat = client.chat
          instructions = BuildInstructions.new(context: context)
          # Two blocks, not one string: the cache breakpoint goes at the end of
          # the first, so what changes every turn has to arrive after it.
          chat.with_instructions(client.cacheable(instructions.stable))
          chat.with_instructions(instructions.volatile, append: true)
          # `calls: :one` disables parallel tool calls, so a single response
          # cannot contain two advance_booking calls.
          chat.with_tools(*tools, calls: :one)
          chat.with_temperature(TEMPERATURE)
          seed_history(chat)

          cap_hops(chat)
          chat
        end

        private

        attr_reader :context, :tools, :recorder, :max_hops

        # The last few turns, added after the instructions and before the
        # message being answered -- which is where RubyLLM::Chat#ask puts it,
        # so the model reads the thread in the order it happened.
        #
        # Safe for caching: providers cache a prefix of tools + system, and
        # messages come after both. Nothing that changes per turn moved up.
        def seed_history(chat)
          context.recent_messages.each do |entry|
            chat.add_message(role: entry[:role], content: entry[:content])
          end
        end

        def cap_hops(chat)
          chat.before_tool_call { raise RunTurn::HopLimitExceeded if recorder.hops >= max_hops }
          chat.after_tool_result { recorder.count_hop! }
        end
      end
    end
  end
end
