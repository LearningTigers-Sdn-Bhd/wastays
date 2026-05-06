module AiConciergeV3
  module Tools
    module HotelInformation
      class GetHotelFaqTool
        def initialize(hotel:)
          @hotel = hotel
        end

        def call
          faq_text = format_faq(hotel.faq)

          {
            "success" => faq_text.present?,
            "faq_text" => faq_text.presence,
            "source" => "hotel_faq"
          }
        end

        private

        attr_reader :hotel

        def format_faq(sections)
          Array(sections).filter_map do |section|
            next unless section.is_a?(Hash)

            section_name = value_for(section, "section_name")
            lines = Array(value_for(section, "items")).filter_map do |item|
              next unless item.is_a?(Hash)

              question = value_for(item, "question")
              answer = value_for(item, "answer")
              next if question.blank? && answer.blank?

              if question.present? && answer.present?
                "- Q: #{question}\n  A: #{answer}"
              elsif question.present?
                "- Q: #{question}"
              else
                "- A: #{answer}"
              end
            end

            next if section_name.blank? && lines.empty?
            next lines.join("\n\n") if section_name.blank?

            ([ section_name ] + lines).join("\n")
          end.join("\n\n")
        end

        def value_for(hash, key)
          hash[key].presence || hash[key.to_sym].presence
        end
      end
    end
  end
end
