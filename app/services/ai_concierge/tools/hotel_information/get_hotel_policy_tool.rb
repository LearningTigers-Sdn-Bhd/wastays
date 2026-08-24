module AiConcierge
  module Tools
    module HotelInformation
      class GetHotelPolicyTool
        def initialize(hotel:, policy_topic: nil, query: nil, scope: nil, hints: Retrieval::QueryHints.none)
          @hotel = hotel
          @policy_topic = policy_topic
          @query = query.to_s
          @hints = hints
          @scope = scope
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
          reply = HybridAnswerBuilder.new(
            hotel: hotel,
            query: query,
            intent: "hotel_policy",
            topic: policy_topic,
            categories: [ "policy" ],
            source: hotel_policy_text.present? ? "hotel_policy" : "property_policy",
            structured_facts: structured_facts,
            fallback_text: hotel_policy_text.presence,
            scope: scope,
            hints: hints
          ).call

          reply.to_h.merge(
            "policy_text" => hotel_policy_text.presence,
            "check_in_time" => structured_facts["check_in_time"],
            "check_out_time" => structured_facts["check_out_time"],
            "cancellation_policy" => structured_facts["cancellation_policy"],
            "policy_topic" => policy_topic
          )
        end

        private

        attr_reader :hotel, :policy_topic, :query, :scope, :hints

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
