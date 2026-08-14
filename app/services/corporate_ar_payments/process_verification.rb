# frozen_string_literal: true

require "ostruct"

module CorporateArPayments
  class ProcessVerification
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(intent:, payment_response:)
      @intent = intent
      @payment_response = payment_response.to_h.symbolize_keys
    end

    def call
      return failure("Corporate settlement is unavailable while this property is in training.") if @intent.hotel.training_mode?

      setting = @intent.hotel.effective_payment_setting(@intent.gateway)
      return failure("Payment gateway is not configured.") unless setting

      adapter = Payments::GatewayRegistry.fetch(gateway: @intent.gateway, setting: setting)
      verification = adapter.verify_client_callback(payment_response: @payment_response)

      CorporateArPayments::CaptureIntent.call(
        intent: @intent,
        gateway: @intent.gateway,
        payment_response: @payment_response,
        verification_result: verification,
        event_source: "corporate_ar_client_callback"
      )
    rescue Payments::GatewayRegistry::UnsupportedGatewayError => e
      failure(e.message)
    rescue StandardError => e
      Rails.logger.error("Corporate AR payment verification error: #{e.message}")
      failure("Unable to verify payment at the moment.")
    end

    private

    def failure(error)
      OpenStruct.new(success?: false, ar_payment: nil, transaction: nil, error: error)
    end
  end
end
