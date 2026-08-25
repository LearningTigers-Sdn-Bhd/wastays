# frozen_string_literal: true

module AiConcierge
  module Tools
    module HotelInformation
      class HybridAnswerBuilder
        STRONG_MATCH_DISTANCE = 0.35
        FALLBACK_CATEGORIES = %w[general_info faq policy].freeze
        CACHE_VERSION = "v3"
        ANSWER_TTL = 6.hours

        def initialize(hotel:, query:, intent:, topic:, categories:, source:, structured_facts: {},
                       fallback_text: nil, scope: nil,
                       hints: Retrieval::QueryHints.none, search_service: HotelKnowledges::SearchService,
                       answer_agent: AiConcierge::Agents::KnowledgeAnswerAgent)
          @hotel = hotel
          @query = query.to_s
          @intent = intent.to_s
          @topic = topic.to_s
          @categories = Array(categories)
          @source = source
          @structured_facts = structured_facts.to_h
          @fallback_text = fallback_text.to_s.presence
          @scope = scope.to_s.presence
          @hints = Retrieval::QueryHints.from(hints)
          @search_service = search_service
          @answer_agent = answer_agent
        end

        def call
          return opening_hours_clarification([]) if ambiguous_opening_hours_question?

          cached = Rails.cache.fetch(cache_key, expires_in: ANSWER_TTL) { build_reply.to_h }
          Orchestration::HotelKnowledge::Reply.from_h(cached)
        end

        private

        def build_reply
          matches = search_matches

          return broad_reply(matches) if broad?
          structured = direct_structured_fact
          return reply(facts: [ structured ], answer_mode: "structured", matches: matches) if structured

          if deterministic_match?(matches)
            return reply(facts: [ fact_from_match(matches.first, 1) ], answer_mode: "deterministic", matches: matches)
          end

          if matches.many?
            synthesized = synthesize(matches)
            return reply(facts: synthesized, answer_mode: "synthesized", matches: matches) if synthesized.present?
            return reply(facts: [ fact_from_match(matches.first, 1) ], answer_mode: "fallback", matches: matches)
          end

          fallback_matches = fallback_search_matches
          if deterministic_match?(fallback_matches)
            return reply(facts: [ fact_from_match(fallback_matches.first, 1) ], answer_mode: "deterministic", matches: fallback_matches)
          end

          if fallback_matches.many?
            synthesized = synthesize(fallback_matches)
            return reply(facts: synthesized, answer_mode: "synthesized", matches: fallback_matches) if synthesized.present?
            return reply(facts: [ fact_from_match(fallback_matches.first, 1) ], answer_mode: "fallback", matches: fallback_matches)
          end

          if ambiguous_policy_question?
            return reply(
              shape: "clarification",
              answer_mode: "unavailable",
              facts: [ fact(topic: "policy", text: "Which policy would you like to know about: check-in, check-out, cancellation, or house rules?") ],
              matches: matches,
              success: false
            )
          end

          if fallback_text.present?
            return reply(
              facts: [ fact(topic: topic_label, text: fallback_text) ],
              answer_mode: "fallback",
              matches: matches
            )
          end

          reply(
            shape: "unavailable",
            answer_mode: "unavailable",
            matches: matches,
            missing_topic: missing_topic,
            success: false
          )
        end

        def broad_reply(matches)
          selected_matches = useful_matches(matches)
          knowledge_facts, knowledge_mode = facts_for_matches(selected_matches)
          structured = structured_broad_facts
          use_legacy = knowledge_facts.empty? && fallback_text.present? && (structured.empty? || topic == "hotel_policy")
          legacy_facts = use_legacy ? [ fact(topic: topic_label, text: fallback_text) ] : []
          facts = (structured + knowledge_facts + legacy_facts).uniq { |item| item.text.downcase.squish }
          mode = if knowledge_facts.present?
            knowledge_mode
          elsif legacy_facts.present?
            "fallback"
          else
            "structured"
          end

          if facts.present?
            visible_facts = facts.first(Orchestration::HotelKnowledge::ReplyComposer::MAX_LIST_FACTS)
            remaining_topics = facts.drop(Orchestration::HotelKnowledge::ReplyComposer::MAX_LIST_FACTS).map(&:topic)
            return reply(
              shape: "list",
              facts: visible_facts,
              remaining_topics: remaining_topics,
              answer_mode: mode,
              matches: selected_matches
            )
          end

          if fallback_text.present?
            return reply(
              shape: "list",
              facts: [ fact(topic: topic_label, text: fallback_text) ],
              answer_mode: "fallback",
              matches: matches
            )
          end

          reply(shape: "unavailable", answer_mode: "unavailable", matches: matches, missing_topic: missing_topic, success: false)
        end

        def useful_matches(matches)
          return matches if deterministic_match?(matches) || matches.many?

          fallback_search_matches
        end

        def facts_for_matches(matches)
          return [ [], nil ] if matches.empty?
          return [ [ fact_from_match(matches.first, 1) ], "deterministic" ] if matches.one?

          synthesized = synthesize(matches)
          return [ synthesized, "synthesized" ] if synthesized.present?

          [ [ fact_from_match(matches.first, 1) ], "fallback" ]
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
            Digest::SHA256.hexdigest([ structured_facts, fallback_text, hints.digest, resolved_scope ].to_json),
            hotel.knowledge_documents.maximum(:updated_at).to_i
          ].join("/")
        end

        attr_reader :hotel, :query, :intent, :topic, :categories, :source, :structured_facts,
          :fallback_text, :scope, :hints, :search_service, :answer_agent

        # A thin first pass sends this same question through a second search
        # over the fallback categories. Both passes embed the identical string,
        # so the vector is resolved through HotelKnowledges::EmbedQuery, whose
        # cache turns the second one into a lookup instead of a round-trip.
        def search_matches(search_categories = categories)
          search_service.new(
            hotel: hotel,
            query: query,
            categories: search_categories,
            keyword_terms: hints.terms,
            preferred_language: hints.preferred_language
          ).call
        end

        def fallback_search_matches
          return [] if query.blank?
          return [] if categories.map(&:to_s).sort == FALLBACK_CATEGORIES.sort

          @fallback_categories_used = FALLBACK_CATEGORIES
          search_matches(FALLBACK_CATEGORIES)
        end

        # The certain answers: no searching, no synthesis, straight off the row
        # the booking engine charges from.
        #
        # Which fact was asked for used to be decided by matching English words
        # in the question, so "几点入住" reached none of them. The model naming
        # the fact is the same reading, done by the half of the system that can
        # read every language -- and the English match stays in front of it, so
        # an English question behaves exactly as it did.
        def direct_structured_fact
          key = asked_fact
          return direct_general_fact if key.blank?

          value = structured_facts[key]
          return if value.blank?

          fact(topic: structured_topic(key), text: structured_text(key, value))
        end

        def direct_general_fact
          return unless topic == "general_hotel_info"

          amenities = Array(structured_facts["amenities"]).compact_blank
          if amenities.any? && amenities_question?
            matching = amenities.select { |amenity| query.downcase.include?(amenity.downcase) }
            matching = amenities if matching.empty?
            return fact(topic: "amenities", text: "Available amenities include #{matching.to_sentence}.")
          end

          location = structured_location
          return fact(topic: "location", text: "The hotel is located at #{location}.") if location.present? && location_question?

          rating = structured_facts["star_rating"]
          fact(topic: "star rating", text: "The hotel has a #{rating}-star rating.") if rating.present? && rating_question?
        end

        def structured_broad_facts
          return structured_policy_facts if topic == "hotel_policy"
          return structured_general_facts if topic == "general_hotel_info"

          []
        end

        def structured_policy_facts
          %w[check_in_time check_out_time cancellation_policy].filter_map do |key|
            value = structured_facts[key]
            fact(topic: structured_topic(key), text: structured_text(key, value)) if value.present?
          end
        end

        def structured_general_facts
          facts = []
          rating = structured_facts["star_rating"]
          facts << fact(topic: "star rating", text: "The hotel has a #{rating}-star rating.") if rating.present?

          location = structured_location
          facts << fact(topic: "location", text: "The hotel is located at #{location}.") if location.present?

          amenities = Array(structured_facts["amenities"]).compact_blank
          facts << fact(topic: "amenities", text: "Available amenities include #{amenities.to_sentence}.") if amenities.any?
          facts
        end

        def structured_location
          %w[address city country].filter_map { |key| structured_facts[key].presence }.join(", ").presence
        end

        def structured_topic(key)
          {
            "check_in_time" => "check-in",
            "check_out_time" => "check-out",
            "cancellation_policy" => "cancellation"
          }.fetch(key, key.tr("_", " "))
        end

        def structured_text(key, value)
          case key
          when "check_in_time" then "You can check in from #{value}."
          when "check_out_time" then "Check-out is by #{value}."
          when "cancellation_policy" then "You can cancel under these terms: #{value.to_s.chomp('.')}."
          else value.to_s
          end
        end

        def asked_fact
          normalized = query.downcase
          return "check_in_time" if normalized.match?(/\bcheck[ -]?in\b/)
          return "check_out_time" if normalized.match?(/\bcheck[ -]?out\b/)
          return "cancellation_policy" if normalized.match?(/\bcancell?ation|cancel\b/)
          return if ambiguous_opening_hours_question?

          hints.fact
        end

        def opening_hours_clarification(matches)
          reply(
            shape: "clarification",
            answer_mode: "unavailable",
            facts: [
              fact(
                topic: "opening hours",
                text: "Do you mean the hotel check-in time or the opening hours of a facility?"
              )
            ],
            matches: matches,
            success: false
          )
        end

        def ambiguous_opening_hours_question?
          normalized = query.downcase
          return false unless normalized.match?(/\bopen(?:ing)?\b|\bopening hours?\b/)
          return false if normalized.match?(/\bcheck[ -]?(?:in|out)\b/)
          return false if normalized.match?(/\b(?:bar|breakfast|cafe|gym|parking|pool|reception|restaurant|shuttle|spa|front desk)\b/)

          true
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
          result = answer_agent.new(
            hotel: hotel,
            message: query,
            intent: intent,
            topic: topic,
            matches: matches,
            structured_facts: structured_facts,
            scope: resolved_scope
          ).call
          coerce_synthesized_facts(result, matches)
        rescue AiConcierge::Agents::KnowledgeAnswerAgent::KnowledgeAnswerError
          nil
        end

        def coerce_synthesized_facts(result, matches)
          return [ fact(topic: topic_label, text: result, source_refs: (1..matches.size).to_a) ] if result.is_a?(String)

          Array(result).filter_map do |item|
            item.is_a?(Orchestration::HotelKnowledge::Reply::Fact) ? item : Orchestration::HotelKnowledge::Reply::Fact.from_h(item)
          end
        end

        def fact_from_match(match, index)
          fact(
            topic: match["document_title"].presence || match["category"].presence || topic_label,
            text: match["content"],
            source_refs: [ index ]
          )
        end

        def fact(topic:, text:, source_refs: [])
          Orchestration::HotelKnowledge::Reply::Fact.new(topic: topic, text: text, source_refs: source_refs)
        end

        def reply(shape: "direct", answer_mode:, facts: [], matches:, remaining_topics: [], missing_topic: nil, success: true)
          Orchestration::HotelKnowledge::Reply.new(
            shape: shape,
            answer_mode: answer_mode,
            facts: facts,
            remaining_topics: remaining_topics,
            missing_topic: missing_topic,
            source: source,
            knowledge_matches: matches,
            searched_categories: categories,
            fallback_categories: @fallback_categories_used || [],
            success: success
          )
        end

        def broad? = resolved_scope == "broad"

        def resolved_scope
          @resolved_scope ||= scope.presence || (broad_question? ? "broad" : "specific")
        end

        def broad_question?
          return false if asked_fact.present?

          query.downcase.match?(
            /\b(?:hotel|your|all|house)\s+(?:policy|policies|rules)\b|\bwhat\s+(?:is|are)\s+(?:the\s+)?(?:policy|policies|rules)\b|\bwhat\b.+\b(?:aware|know)\b.+\b(?:book|booking|hotel|stay)\b|\b(?:tell me about|information about|overview of)\b.+\bhotel\b/
          )
        end

        def topic_label = topic.tr("_", " ").presence || categories.first.to_s.tr("_", " ")

        def missing_topic
          return "#{structured_topic(asked_fact)} details" if asked_fact.present?
          return "service information" if service_question?

          case topic
          when "hotel_policy" then "policy information"
          when "hotel_faq" then "an FAQ answer"
          when "general_hotel_info" then "hotel information"
          else topic_label.presence || "that information"
          end
        end

        def service_question?
          query.downcase.match?(/\b(?:airport transfer|breakfast|parking|pool|restaurant|room service|shuttle|spa|transport|wi-?fi)\b/)
        end

        def ambiguous_policy_question?
          scope == "specific" && topic == "hotel_policy" &&
            query.downcase.match?(/\bpolic(?:y|ies)\b/) &&
            !query.downcase.match?(/\b(?:cancel|check[ -]?(?:in|out)|pet|quiet|smok|visitor|house rule)\b/)
        end

        def amenities_question?
          service_question? || query.downcase.match?(/\b(?:amenit|facilit)/)
        end

        def location_question?
          query.downcase.match?(/\b(?:address|located|location|where)\b/)
        end

        def rating_question?
          query.downcase.match?(/\b(?:rating|star)\b/)
        end
      end
    end
  end
end
