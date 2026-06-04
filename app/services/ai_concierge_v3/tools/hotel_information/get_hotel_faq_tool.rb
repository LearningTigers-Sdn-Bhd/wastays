module AiConciergeV3
  module Tools
    module HotelInformation
      class GetHotelFaqTool
        def initialize(hotel:, query: nil)
          @hotel = hotel
          @query = query.to_s
        end

        def call
          documents = hotel.knowledge_documents.where(category: "faq", embedding_status: "indexed").includes(:chunks)
          faq_text = format_documents(documents)
          answer_payload = HybridAnswerBuilder.new(
            hotel: hotel,
            query: query,
            intent: "hotel_information",
            topic: "hotel_faq",
            categories: [ "faq" ],
            source: "hotel_faq",
            fallback_text: faq_text.presence,
            unavailable_answer: "The hotel has not provided FAQ details yet."
          ).call

          {
            "success" => answer_payload["success"],
            "answer" => answer_payload["answer"],
            "answer_mode" => answer_payload["answer_mode"],
            "faq_text" => faq_text.presence,
            "source" => "hotel_faq",
            "knowledge_matches" => answer_payload["knowledge_matches"],
            "searched_categories" => answer_payload["searched_categories"],
            "fallback_categories" => answer_payload["fallback_categories"]
          }
        end

        private

        attr_reader :hotel, :query

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
