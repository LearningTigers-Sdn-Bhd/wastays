# frozen_string_literal: true

module Notifications
  class DeliverJob < ApplicationJob
    queue_as :default

    def perform(delivery_id, expected_scheduled_for = nil)
      delivery = NotificationDelivery.find_by(id: delivery_id)
      return unless delivery
      return if delivery.status == "sent"
      return if stale_schedule?(delivery, expected_scheduled_for)
      if delivery.hotel.training_mode?
        delivery.update!(status: "skipped", failed_at: nil, error_message: "Guest messaging is unavailable while this property is in training.")
        return
      end

      adapter_for(delivery).call
      delivery.update!(status: "sent", sent_at: Time.current, failed_at: nil, error_message: nil)
    rescue Notifications::InvoiceDelivery::UnavailableError => e
      delivery&.update!(status: "skipped", failed_at: nil, error_message: e.message)
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

    def stale_schedule?(delivery, expected_scheduled_for)
      return false if expected_scheduled_for.blank?

      current = delivery.payload.to_h["scheduled_for"]
      current.present? && current != expected_scheduled_for
    end
  end
end
