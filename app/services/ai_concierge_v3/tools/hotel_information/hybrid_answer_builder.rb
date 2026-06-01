# frozen_string_literal: true

module AiConciergeV3
  module Tools
    module HotelInformation
      class HybridAnswerBuilder
        STRONG_MATCH_DISTANCE = 0.35

        def initialize(hotel:, query:, intent:, topic:, categories:, source:, structured_facts: {}, fallback_text: nil, unavailable_answer: nil, search_service: HotelKnowledges::SearchService, answer_agent: AiConciergeV3::Agents::KnowledgeAnswerAgent)
          @hotel = hotel
          @query = query.to_s
          @intent = intent.to_s
          @topic = topic.to_s
          @categories = Array(categories)
          @source = source
          @structured_facts = structured_facts.to_h
          @fallback_text = fallback_text.to_s.presence
          @unavailable_answer = unavailable_answer.presence || "The hotel has not provided that information yet."
          @search_service = search_service
          @answer_agent = answer_agent
        end

        def call
          matches = search_matches

          if direct_structured_answer.present?
            return payload(answer: direct_structured_answer, answer_mode: "fallback", matches: matches)
          end

          if deterministic_match?(matches)
            return payload(answer: matches.first["content"], answer_mode: "deterministic", matches: matches)
          end

          if matches.many?
            synthesized = synthesize(matches)
            return payload(answer: synthesized, answer_mode: "synthesized", matches: matches) if synthesized.present?
            return payload(answer: deterministic_fallback(matches), answer_mode: "deterministic", matches: matches)
          end

          return payload(answer: fallback_text, answer_mode: "fallback", matches: matches) if fallback_text.present?

          payload(answer: unavailable_answer, answer_mode: "unavailable", matches: matches, success: false)
        end

        private

        attr_reader :hotel, :query, :intent, :topic, :categories, :source, :structured_facts,
          :fallback_text, :unavailable_answer, :search_service, :answer_agent

        def search_matches
          search_service.new(hotel: hotel, query: query, categories: categories).call
        end

        def direct_structured_answer
          normalized = query.downcase
          if normalized.match?(/\bcheck[ -]?in\b/) && structured_facts["check_in_time"].present?
            return "Check-in starts at #{structured_facts['check_in_time']}."
          end

          if normalized.match?(/\bcheck[ -]?out\b/) && structured_facts["check_out_time"].present?
            return "Check-out is at #{structured_facts['check_out_time']}."
          end

          if normalized.match?(/\bcancell?ation|cancel\b/) && structured_facts["cancellation_policy"].present?
            return "Cancellation policy: #{structured_facts['cancellation_policy']}."
          end

          nil
        end

        def deterministic_match?(matches)
          return false unless matches.one?

          distance = matches.first["distance"]
          distance.blank? || distance.to_f <= STRONG_MATCH_DISTANCE
        end

        def synthesize(matches)
          answer_agent.new(
            hotel: hotel,
            message: query,
            intent: intent,
            topic: topic,
            matches: matches,
            structured_facts: structured_facts
          ).call
        rescue AiConciergeV3::Agents::KnowledgeAnswerAgent::KnowledgeAnswerError
          nil
        end

        def deterministic_fallback(matches)
          matches.first&.fetch("content", nil).presence || fallback_text || unavailable_answer
        end

        def payload(answer:, answer_mode:, matches:, success: true)
          {
            "success" => success,
            "answer" => answer,
            "answer_mode" => answer_mode,
            "source" => source,
            "knowledge_matches" => matches
          }
        end
      end
    end
  end
end
