# frozen_string_literal: true

module AiConcierge
  module Tools
    module HotelInformation
      class HybridAnswerBuilder
        STRONG_MATCH_DISTANCE = 0.35
        FALLBACK_CATEGORIES = %w[general_info faq policy].freeze
        CACHE_VERSION = "v1"
        ANSWER_TTL = 6.hours

        def initialize(hotel:, query:, intent:, topic:, categories:, source:, structured_facts: {}, fallback_text: nil, unavailable_answer: nil, search_service: HotelKnowledges::SearchService, answer_agent: AiConcierge::Agents::KnowledgeAnswerAgent)
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
          Rails.cache.fetch(cache_key, expires_in: ANSWER_TTL) { build_answer }
        end

        private

        def build_answer
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

          fallback_matches = fallback_search_matches
          if deterministic_match?(fallback_matches)
            return payload(answer: fallback_matches.first["content"], answer_mode: "deterministic", matches: fallback_matches)
          end

          if fallback_matches.many?
            synthesized = synthesize(fallback_matches)
            return payload(answer: synthesized, answer_mode: "synthesized", matches: fallback_matches) if synthesized.present?
            return payload(answer: deterministic_fallback(fallback_matches), answer_mode: "deterministic", matches: fallback_matches)
          end

          return payload(answer: fallback_text, answer_mode: "fallback", matches: matches) if fallback_text.present?

          payload(answer: unavailable_answer, answer_mode: "unavailable", matches: matches, success: false)
        end

        # Hotel facts change monthly; the questions arrive hourly. Caching the
        # answer also caches away the synthesis call to a model, which is the
        # expensive half of a miss.
        #
        # Everything the answer is derived from is in the key, so nothing has
        # to remember to invalidate this: the corpus timestamp moves when a
        # document is re-ingested, and the structured facts and fallback text
        # are digested rather than assumed constant -- a hotel that changes its
        # check-in time must not keep being asked to honour the old one.
        def cache_key
          [
            "ai_concierge/hotel_answer",
            CACHE_VERSION,
            hotel.id,
            source,
            categories.map(&:to_s).sort.join(","),
            Digest::SHA256.hexdigest(query.downcase.squish),
            Digest::SHA256.hexdigest([ structured_facts, fallback_text ].to_json),
            hotel.knowledge_documents.maximum(:updated_at).to_i
          ].join("/")
        end

        attr_reader :hotel, :query, :intent, :topic, :categories, :source, :structured_facts,
          :fallback_text, :unavailable_answer, :search_service, :answer_agent

        # A thin first pass sends this same question through a second search
        # over the fallback categories. Both passes embed the identical string,
        # so the vector is resolved through HotelKnowledges::EmbedQuery, whose
        # cache turns the second one into a lookup instead of a round-trip.
        def search_matches(search_categories = categories)
          search_service.new(hotel: hotel, query: query, categories: search_categories).call
        end

        def fallback_search_matches
          return [] if query.blank?
          return [] if categories.map(&:to_s).sort == FALLBACK_CATEGORIES.sort

          @fallback_categories_used = FALLBACK_CATEGORIES
          search_matches(FALLBACK_CATEGORIES)
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
            return "Cancellation policy: #{structured_facts['cancellation_policy'].to_s.chomp('.')}."
          end

          nil
        end

        # Returning a chunk verbatim is the strongest thing this class does, so
        # it wants a strong reason.
        #
        # Two retrievers agreeing is the best one available -- better than any
        # distance threshold, because they fail differently. A chunk only
        # keyword search found is the opposite: it matched some words, which is
        # how it got here, but nothing has vouched for what it means. Those go
        # on to the fallback search and synthesis rather than being quoted at
        # the guest, which is exactly where they would have ended up before
        # keyword search existed.
        def deterministic_match?(matches)
          return false unless matches.one?

          retrieval = Array(matches.first["retrieval"])
          return true if retrieval.uniq.many?
          return false if retrieval == [ "keyword" ]

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
        rescue AiConcierge::Agents::KnowledgeAnswerAgent::KnowledgeAnswerError
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
            "knowledge_matches" => matches,
            "searched_categories" => categories,
            "fallback_categories" => @fallback_categories_used || []
          }
        end
      end
    end
  end
end
