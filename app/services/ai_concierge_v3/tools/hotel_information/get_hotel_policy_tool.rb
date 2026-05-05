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
          hotel_policy_text = hotel.policy.to_s.strip

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
      end
    end
  end
end
