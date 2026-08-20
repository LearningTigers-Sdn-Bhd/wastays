# frozen_string_literal: true

require "ruby_llm"

module AiConcierge
  module Providers
    class RubyLlmClient
      def initialize(hotel:)
        @hotel = hotel
      end

      def chat
        chat = context.chat(
          model: hotel.ai_concierge_model_name,
          provider: hotel.ai_concierge_provider
        )
        disable_thinking(chat)
        chat
      end

      private

      attr_reader :hotel

      # Gemini 2.5 thinks by default, and nothing here ever told it not to.
      # Those tokens bill as output -- the dearest tokens gemini sells -- and
      # they are spent before a word reaches a guest who is waiting on
      # WhatsApp, twice a turn, on work that is picking a tool and rewriting a
      # sentence. No accounting exists anywhere in this namespace, so it has
      # been paid for silently.
      #
      # A budget of zero is how gemini is told to stop: `Thinking::Config` is
      # enabled by any budget including 0, which is what makes the request
      # carry `thinkingBudget: 0` at all. Gated by provider on purpose --
      # openai turns the same config into `reasoning_effort`, which the model
      # in that seat does not take.
      def disable_thinking(chat)
        return unless hotel.ai_provider_name == "gemini"

        chat.with_thinking(budget: 0)
      end

      def context
        RubyLLM.context do |config|
          case hotel.ai_provider_name
          when "openai"
            config.openai_api_key = hotel.ai_concierge_api_key
          when "claude"
            config.anthropic_api_key = hotel.ai_concierge_api_key
          when "gemini"
            config.gemini_api_key = hotel.ai_concierge_api_key
          end
        end
      end
    end
  end
end
