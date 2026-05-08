# frozen_string_literal: true

module Notifications
  module Channels
    class WhatsappWebhook
      EVENT_NAME = "check_in_confirmation"

      def initialize(delivery:)
        @delivery = delivery
      end

      def call
        WebhookBroadcastJob.perform_now(EVENT_NAME, @delivery.payload)
      end
    end
  end
end
