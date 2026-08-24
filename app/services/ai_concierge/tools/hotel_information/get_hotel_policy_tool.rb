module AiConcierge
  module Tools
    module HotelInformation
      class GetHotelPolicyTool
        def initialize(hotel:, policy_topic: nil, query: nil, hints: Retrieval::QueryHints.none)
          @hotel = hotel
          @policy_topic = policy_topic
          @query = query.to_s
          @hints = hints
        end

        def call
          policy = hotel.property_policy
          documents = hotel.knowledge_documents.where(category: "policy", embedding_status: "indexed").includes(:chunks)
          hotel_policy_text = format_documents(documents)
          # The concierge answers in prose, so the structured tiers are flattened to
          # text here — from the same rows the engine charges from, never re-typed.
          cancellation = Cancellations::PolicySummary.for_hotel(hotel)
          structured_facts = {
            "check_in_time" => policy&.check_in_time,
            "check_out_time" => policy&.check_out_time,
            "cancellation_policy" => cancellation.to_line.presence
          }
          answer_payload = HybridAnswerBuilder.new(
            hotel: hotel,
            query: query,
            intent: "hotel_policy",
            topic: policy_topic,
            categories: [ "policy" ],
            source: hotel_policy_text.present? ? "hotel_policy" : "property_policy",
            structured_facts: structured_facts,
            fallback_text: hotel_policy_text.presence,
            unavailable_answer: "The hotel has not provided its policy details yet.",
            hints: hints
          ).call
          # A hotel can now have a cancellation policy without a property_policy row,
          # so "we know something" is no longer only about property_policy.
          policy_known = policy.present? || cancellation.present?
          answer_payload["answer"] = nil if answer_payload["answer_mode"] == "unavailable" && policy_known

          {
            "success" => answer_payload["success"] || hotel_policy_text.present? || policy_known,
            "answer" => answer_payload["answer"],
            "answer_mode" => answer_payload["answer_mode"],
            "policy_text" => hotel_policy_text.presence,
            "check_in_time" => structured_facts["check_in_time"],
            "check_out_time" => structured_facts["check_out_time"],
            "cancellation_policy" => structured_facts["cancellation_policy"],
            "policy_topic" => policy_topic,
            "source" => answer_payload["source"],
            "knowledge_matches" => answer_payload["knowledge_matches"],
            "searched_categories" => answer_payload["searched_categories"],
            "fallback_categories" => answer_payload["fallback_categories"]
          }
        end

        private

        attr_reader :hotel, :policy_topic, :query, :hints

        def format_documents(documents)
          documents.filter_map do |doc|
            title = doc.title.presence
            chunks = doc.chunks.order(:chunk_index).map(&:content)
            next if chunks.empty?

            ([ title ] + chunks).compact.join("\n")
          end.join("\n\n")
        end
      end
    end
  end
end
