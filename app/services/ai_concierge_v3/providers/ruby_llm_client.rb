# frozen_string_literal: true

require "ruby_llm"

module AiConciergeV3
  module Providers
    class RubyLlmClient
      def initialize(hotel:)
        @hotel = hotel
      end

      def chat
        context.chat(
          model: hotel.ai_concierge_model_name,
          provider: hotel.ai_concierge_provider
        )
      end

      def structured_output_supported?
        hotel.ai_concierge_structured_output_supported?
      end

      private

      attr_reader :hotel

      def context
        RubyLLM.context do |config|
          case hotel.ai_provider_name
          when "openai"
            config.openai_api_key = hotel.ai_concierge_api_key
          when "claude"
            config.anthropic_api_key = hotel.ai_concierge_api_key
          when "gemini"
            config.gemini_api_key = hotel.ai_concierge_api_key
          when "deepseek"
            config.deepseek_api_key = hotel.ai_concierge_api_key
          end
        end
      end
    end
  end
end
