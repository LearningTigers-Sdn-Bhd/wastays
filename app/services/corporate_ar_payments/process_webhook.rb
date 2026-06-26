# frozen_string_literal: true

require "ostruct"

module CorporateArPayments
  class ProcessWebhook
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(intent:, gateway:, processed_payload:, webhook_payload:)
      @intent = intent
      @gateway = gateway
      @processed_payload = processed_payload.to_h.symbolize_keys
      @webhook_payload = webhook_payload
    end

    def call
      CorporateArPayments::CaptureIntent.call(
        intent: @intent,
        gateway: @gateway,
        payment_response: {
          razorpay_payment_id: @processed_payload[:external_reference],
          razorpay_order_id: @processed_payload[:gateway_order_id]
        },
        verification_result: @processed_payload,
        event_source: "corporate_ar_webhook"
      )
    end
  end
end
