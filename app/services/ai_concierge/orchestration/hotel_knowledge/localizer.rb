# frozen_string_literal: true

require "ruby_llm"

module AiConcierge
  module Orchestration
    module HotelKnowledge
      # Translates finished knowledge copy without giving a second writer room
      # to add greetings, sign-offs or new hotel facts.
      class Localizer
        class LocalizationError < StandardError; end

        LLM_TIMEOUT = 15
        TEMPERATURE = 0

        def initialize(hotel:, reply:, language:)
          @hotel = hotel
          @reply = reply.to_s
          @language = language.to_s.presence || Conversation::DEFAULT_LANGUAGE
        end

        def call
          return reply if language == Conversation::DEFAULT_LANGUAGE

          response = Timeout.timeout(LLM_TIMEOUT) { chat.ask(prompt) }
          Providers::UsageLog.call(response, hotel: hotel, stage: :knowledge_translation)
          candidate = parse(response&.content.to_s)
          valid_translation?(candidate) ? candidate : reply
        rescue Timeout::Error, RubyLLM::Error, LocalizationError => e
          Rails.logger.warn("AiConcierge::HotelKnowledge::Localizer skipped: #{e.message}")
          reply
        end

        private

        attr_reader :hotel, :reply, :language

        def chat
          Providers::RubyLlmClient.new(hotel: hotel).chat.with_temperature(TEMPERATURE)
        end

        def prompt
          <<~PROMPT
            Translate this hotel reply into #{language}.

            REPLY:
            #{reply}

            RULES:
            - Translate only. Do not add or remove a fact.
            - Keep every number, time, currency, link and proper name unchanged.
            - Keep the same line breaks and bullet count.
            - Do not add a greeting, thank-you, sign-off or offer of more help.

            Reply with JSON only:
            {"text":"translated reply"}
          PROMPT
        end

        def parse(content)
          json = content[/\{.*\}/m]
          raise LocalizationError, "translation returned no JSON" if json.blank?

          text = JSON.parse(json)["text"].to_s.strip
          raise LocalizationError, "translation returned empty text" if text.blank?

          text
        rescue JSON::ParserError => e
          raise LocalizationError, "translation returned malformed JSON: #{e.message}"
        end

        def valid_translation?(candidate)
          return false unless bullet_count(candidate) == bullet_count(reply)
          return false unless candidate.lines.size == reply.lines.size

          Agents::RewriteVerifier.new(
            template: reply,
            candidate: candidate,
            protected_names: hotel.room_types.pluck(:name) + hotel.rate_plans.pluck(:name)
          ).call.present?
        end

        def bullet_count(text) = text.lines.count { |line| line.start_with?("- ") }
      end
    end
  end
end
