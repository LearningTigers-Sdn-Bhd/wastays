module AiConciergeV3
  module Tools
    module HotelInformation
      class GetHotelFaqTool
        def initialize(hotel:)
          @hotel = hotel
        end

        def call
          documents = hotel.knowledge_documents.where(category: "faq").includes(:chunks)
          faq_text = format_documents(documents)

          {
            "success" => faq_text.present?,
            "faq_text" => faq_text.presence,
            "source" => "hotel_faq"
          }
        end

        private

        attr_reader :hotel

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
