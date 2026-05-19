# frozen_string_literal: true

require "ostruct"

module Payments
  class InitializeCheckout
    include ActiveModel::Validations

    attr_reader :quote, :gateway, :guest_details, :callback_url

    validates :quote, :gateway, :callback_url, presence: true

    def initialize(quote:, callback_url:, gateway: nil, guest_details: {})
      @quote = quote
      @gateway = gateway || quote.hotel.checkout_payment_gateway || "razorpay"
      @guest_details = guest_details
      @callback_url = callback_url
    end

    def call
      return failure("Invalid parameters") unless valid?

      if quote.partner.present? && quote.partner.domain.present?
        unless valid_partner_email?
          return failure("This corporate rate is only valid for @#{quote.partner.domain} email addresses. Please use your work email.")
        end
      end

      setting = quote.hotel.effective_payment_setting(gateway)
      return failure("Payment gateway is not configured.") unless setting

      adapter = Payments::GatewayRegistry.fetch(gateway: gateway, setting: setting)
      payload = adapter.create_checkout_session(
        amount: quote.total_amount,
        currency: quote.currency,
        description: "Booking payment for #{quote.hotel.name}",
        metadata: session_metadata,
        callback_url: callback_url
      )

      success(payload.merge(gateway: gateway))
    rescue Payments::GatewayRegistry::UnsupportedGatewayError => e
      failure(e.message)
    rescue StandardError => e
      Rails.logger.error("Payment checkout session error: #{e.message}")
      failure("Unable to initialize payment at the moment.")
    end

    private

    def session_metadata
      {
        quote_token: quote.token,
        guest_name: guest_details[:name],
        guest_email: guest_details[:email],
        guest_phone: guest_details[:phone],
        government_id: guest_details[:government_id],
        gender: guest_details[:gender],
        country: guest_details[:country],
        document_type: guest_details[:document_type],
        marketing_consent: guest_details[:marketing_consent]
      }
    end

    def valid_partner_email?
      email = guest_details[:email].to_s.strip.downcase
      return false if email.blank?

      email_domain = email.split("@").last
      email_domain == quote.partner.domain
    end

    def success(payload)
      OpenStruct.new(success?: true, payload: payload)
    end

    def failure(message)
      OpenStruct.new(success?: false, error: message)
    end
  end
end
