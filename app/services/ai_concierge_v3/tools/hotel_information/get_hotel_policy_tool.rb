module AiConciergeV3
  module Tools
    module HotelInformation
      class GetHotelPolicyTool
        def initialize(hotel:, policy_topic: nil)
          @hotel = hotel
          @policy_topic = policy_topic
        end

        def call
          policy = hotel.property_policy
          hotel_policy_text = format_policy(hotel.policy)

          {
            "success" => hotel_policy_text.present? || policy.present?,
            "policy_text" => hotel_policy_text.presence,
            "check_in_time" => policy&.check_in_time,
            "check_out_time" => policy&.check_out_time,
            "cancellation_policy" => policy&.cancellation_policy.presence,
            "policy_topic" => policy_topic,
            "source" => hotel_policy_text.present? ? "hotel_policy" : "property_policy"
          }
        end

        private

        attr_reader :hotel, :policy_topic

        def format_policy(items)
          Array(items).filter_map do |item|
            next unless item.is_a?(Hash)

            title = value_for(item, "title").to_s.strip
            content = value_for(item, "content").to_s.strip
            next if title.blank? && content.blank?

            if title.present? && content.present?
              "#{title}: #{content}"
            else
              title.presence || content
            end
          end.join("\n\n")
        end

        def value_for(hash, key)
          hash[key].presence || hash[key.to_sym].presence
        end
      end
    end
  end
end
