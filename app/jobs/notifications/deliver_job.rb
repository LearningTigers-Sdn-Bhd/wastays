# frozen_string_literal: true

module Notifications
  class DeliverJob < ApplicationJob
    queue_as :default

    def perform(delivery_id)
      delivery = NotificationDelivery.find_by(id: delivery_id)
      return unless delivery
      return if delivery.status == "sent"

      adapter_for(delivery).call
      delivery.update!(status: "sent", sent_at: Time.current, failed_at: nil, error_message: nil)
    rescue StandardError => e
      delivery&.update!(status: "failed", failed_at: Time.current, error_message: e.message)
      raise
    end

    private

    def adapter_for(delivery)
      case delivery.channel
      when "email"
        Notifications::Channels::Email.new(delivery: delivery)
      when "whatsapp"
        Notifications::Channels::WhatsappWebhook.new(delivery: delivery)
      else
        raise ArgumentError, "Unsupported delivery channel: #{delivery.channel}"
      end
    end
  end
end
