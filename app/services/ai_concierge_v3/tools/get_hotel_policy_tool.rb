module AiConciergeV3
  module Tools
    class GetHotelPolicyTool
      def initialize(hotel:, policy_topic: nil)
        @hotel = hotel
        @policy_topic = policy_topic
      end

      def call
        policy = hotel.property_policy
        {
          "check_in_time" => policy&.check_in_time || "not provided yet",
          "check_out_time" => policy&.check_out_time || "not provided yet",
          "cancellation_policy" => policy&.cancellation_policy.presence || "The hotel has not provided that information yet.",
          "policy_topic" => policy_topic
        }
      end

      private

      attr_reader :hotel, :policy_topic
    end
  end
end
