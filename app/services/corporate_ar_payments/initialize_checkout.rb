# frozen_string_literal: true

require "ostruct"

module CorporateArPayments
  class InitializeCheckout
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(intent:, callback_url:)
      @intent = intent
      @callback_url = callback_url
    end

    def call
      return failure("Corporate settlement is unavailable while this property is in training.") if @intent.hotel.training_mode?
      return failure("Corporate relationship is not available for payment.") unless @intent.hotel_corporate_account.active?
      return failure("Payment request has expired.") if @intent.expired_for_checkout?
      return failure("Only Razorpay is available for corporate AR payments.") unless @intent.gateway == "razorpay"

      setting = @intent.hotel.effective_payment_setting(@intent.gateway)
      return failure("Payment gateway is not configured.") unless setting

      adapter = Payments::GatewayRegistry.fetch(gateway: @intent.gateway, setting: setting)
      payload = adapter.create_checkout_session(
        amount: @intent.amount,
        currency: @intent.currency,
        description: "Corporate AR payment for #{@intent.hotel.name}",
        metadata: checkout_metadata,
        callback_url: @callback_url
      )

      @intent.update!(status: "checkout_initiated", gateway_order_id: payload[:order_id] || payload["order_id"])
      record_transaction(payload)
      success(payload.merge(gateway: @intent.gateway))
    rescue Payments::GatewayRegistry::UnsupportedGatewayError => e
      failure(e.message)
    rescue StandardError => e
      Rails.logger.error("Corporate AR checkout session error: #{e.message}")
      failure("Unable to initialize payment at the moment.")
    end

    private

    def checkout_metadata
      {
        quote_token: "corp-ar-#{@intent.id}",
        payment_context: "corporate_ar",
        corporate_ar_payment_intent_id: @intent.id,
        hotel_id: @intent.hotel_id,
        hotel_corporate_account_id: @intent.hotel_corporate_account_id,
        corporate_account_id: @intent.corporate_account_id
      }
    end

    def record_transaction(payload)
      PaymentTransaction.find_or_initialize_by(gateway: @intent.gateway, gateway_order_id: payload[:order_id] || payload["order_id"]).tap do |transaction|
        transaction.assign_attributes(
          corporate_ar_payment_intent: @intent,
          gateway: @intent.gateway,
          status: "checkout_initiated",
          amount_subunits: payload[:amount] || payload["amount"],
          currency: payload[:currency] || payload["currency"],
          event_source: "corporate_ar_checkout_session",
          metadata: checkout_metadata,
          gateway_payload: payload
        )
        transaction.save!
      end
    end

    def success(payload)
      OpenStruct.new(success?: true, payload: payload, error: nil)
    end

    def failure(error)
      OpenStruct.new(success?: false, payload: nil, error: error)
    end
  end
end
