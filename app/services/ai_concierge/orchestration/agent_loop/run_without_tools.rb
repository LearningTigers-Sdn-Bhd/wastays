# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module AgentLoop
      # For a provider whose native tool calling cannot be relied on.
      #
      # One hop, no loop: the model is asked to name a tool and its arguments as
      # JSON, and the *same* tool instances run it. Only the transport differs,
      # so there is no second set of loop semantics to reason about -- the
      # multi-hop path can only ever add refinement, never a different final
      # action.
      class RunWithoutTools
        def initialize(context:, tools:)
          @context = context
          @tools = tools
        end

        def call
          parsed = JSON.parse(response_content)
          tool = tools.find { |candidate| candidate.name == parsed["tool"].to_s }
          return answer_as_question unless tool

          tool.call(parsed["arguments"] || {})
        rescue JSON::ParserError
          # Knowledge is stateless and cheap to be wrong about. Guessing here
          # never touches booking state and cannot write a quote.
          answer_as_question
        end

        private

        attr_reader :context, :tools

        def response_content
          chat = Providers::RubyLlmClient.new(hotel: context.hotel).chat
          chat.with_temperature(BuildChat::TEMPERATURE)
          chat.ask(prompt)&.content.to_s
        end

        def answer_as_question
          tools.find { |tool| tool.name == "answer_hotel_question" }
               &.call({ "question" => context.message })
        end

        def prompt
          <<~PROMPT
            #{BuildInstructions.new(context: context).call}

            The tools available to you:
            #{tool_menu}

            Reply with JSON only, in exactly this shape, and nothing else:
            {"tool": "<tool name>", "arguments": {}}

            GUEST MESSAGE: #{context.message}
          PROMPT
        end

        def tool_menu
          tools.map { |tool| "- #{tool.name}: #{tool.description.to_s.squish}" }.join("\n")
        end
      end
    end
  end
end
