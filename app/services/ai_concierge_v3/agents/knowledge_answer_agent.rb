# frozen_string_literal: true

require "ruby_llm"

module AiConciergeV3
  module Agents
    class KnowledgeAnswerAgent
      class KnowledgeAnswerError < StandardError; end

      LLM_TIMEOUT = 30

      def initialize(hotel:, message:, intent:, topic:, matches:, structured_facts: {})
        @hotel = hotel
        @message = message.to_s.strip
        @intent = intent.to_s
        @topic = topic.to_s
        @matches = Array(matches)
        @structured_facts = structured_facts.to_h
      end

      def call
        response = Timeout.timeout(LLM_TIMEOUT) { chat.ask(prompt) }
        content = response&.content.to_s.strip
        raise KnowledgeAnswerError, "Empty response from LLM" if content.blank?

        content
      rescue Timeout::Error
        raise KnowledgeAnswerError, "Knowledge answer request timed out after #{LLM_TIMEOUT}s"
      rescue RubyLLM::Error => e
        raise KnowledgeAnswerError, "Knowledge answer API error: #{e.message}"
      end

      private

      attr_reader :hotel, :message, :intent, :topic, :matches, :structured_facts

      def chat
        context.chat(
          model: hotel.ai_concierge_model_name,
          provider: hotel.ai_concierge_provider
        )
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
          when "deepseek"
            config.deepseek_api_key = hotel.ai_concierge_api_key
          end
        end
      end

      def prompt
        <<~PROMPT
          You are answering a hotel guest question for #{hotel.name}.

          USER QUESTION:
          #{message}

          INTENT: #{intent}
          TOPIC: #{topic}

          HOTEL KNOWLEDGE SNIPPETS:
          #{matches_for_prompt}

          STRUCTURED HOTEL FACTS:
          #{structured_facts.to_json}

          RULES:
          - Answer only from HOTEL KNOWLEDGE SNIPPETS and STRUCTURED HOTEL FACTS.
          - Do not invent prices, times, availability, amenities, exceptions, or policies.
          - If the provided information is insufficient, say the hotel has not provided that information yet.
          - Keep the answer concise, friendly, and guest-facing.
          - Do not mention sources, documents, snippets, internal metadata, or citations.
        PROMPT
      end

      def matches_for_prompt
        return "None." if matches.empty?

        matches.each_with_index.map do |match, index|
          title = match["document_title"].presence || "Untitled"
          category = match["category"].presence || "knowledge"
          "#{index + 1}. [#{category} / #{title}] #{match['content']}"
        end.join("\n")
      end
    end
  end
end
