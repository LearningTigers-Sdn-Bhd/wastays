module AiConcierge
  module Tools
    module HotelInformation
      class GetHotelFaqTool
        def initialize(hotel:, query: nil, scope: nil, hints: Retrieval::QueryHints.none)
          @hotel = hotel
          @query = query.to_s
          @hints = hints
          @scope = scope
        end

        def call
          documents = hotel.knowledge_documents
            .where(category: "faq", embedding_status: "indexed")
            .order(:created_at, :id)
            .includes(:chunks)
          faq_text = format_documents(documents)
          reply = HybridAnswerBuilder.new(
            hotel: hotel,
            query: query,
            intent: "hotel_information",
            topic: "hotel_faq",
            categories: [ "faq" ],
            source: "hotel_faq",
            fallback_text: faq_text.presence,
            scope: scope,
            hints: hints
          ).call

          reply.to_h.merge(
            "faq_text" => faq_text.presence,
          )
        end

        private

        attr_reader :hotel, :query, :scope, :hints

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
