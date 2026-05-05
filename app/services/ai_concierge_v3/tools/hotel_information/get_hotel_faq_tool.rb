module AiConciergeV3
  module Tools
    module HotelInformation
      class GetHotelFaqTool
        def initialize(hotel:)
          @hotel = hotel
        end

        def call
          faq_text = hotel.faq.to_s.strip

          {
            "success" => faq_text.present?,
            "faq_text" => faq_text.presence,
            "source" => "hotel_faq"
          }
        end

        private

        attr_reader :hotel
      end
    end
  end
end
