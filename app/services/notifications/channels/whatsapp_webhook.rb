# frozen_string_literal: true

module Notifications
  module Channels
    class WhatsappWebhook
      EVENT_NAMES = {
        "check_in_confirmation" => "check_in_confirmation",
        "post_stay_review_request" => "post_stay_review_request",
        "pre_arrival_notification" => "pre_arrival_notification"
      }.freeze

      def initialize(delivery:)
        @delivery = delivery
      end

      def call
        WebhookBroadcastJob.perform_now(event_name, @delivery.payload)
      end

      private

      def event_name
        EVENT_NAMES.fetch(@delivery.notification_type)
      end
    end
  end
end
