module AiConciergeV3
  module Tools
    module HotelInformation
      class GetHotelPolicyTool
        def initialize(hotel:, policy_topic: nil, query: nil)
          @hotel = hotel
          @policy_topic = policy_topic
          @query = query.to_s
        end

        def call
          policy = hotel.property_policy
          documents = hotel.knowledge_documents.where(category: "policy", embedding_status: "indexed").includes(:chunks)
          hotel_policy_text = format_documents(documents)
          structured_facts = {
            "check_in_time" => policy&.check_in_time,
            "check_out_time" => policy&.check_out_time,
            "cancellation_policy" => policy&.cancellation_policy.presence
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
            unavailable_answer: "The hotel has not provided its policy details yet."
          ).call
          answer_payload["answer"] = nil if answer_payload["answer_mode"] == "unavailable" && policy.present?

          {
            "success" => answer_payload["success"] || hotel_policy_text.present? || policy.present?,
            "answer" => answer_payload["answer"],
            "answer_mode" => answer_payload["answer_mode"],
            "policy_text" => hotel_policy_text.presence,
            "check_in_time" => structured_facts["check_in_time"],
            "check_out_time" => structured_facts["check_out_time"],
            "cancellation_policy" => structured_facts["cancellation_policy"],
            "policy_topic" => policy_topic,
            "source" => answer_payload["source"],
            "knowledge_matches" => answer_payload["knowledge_matches"]
          }
        end

        private

        attr_reader :hotel, :policy_topic, :query

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
