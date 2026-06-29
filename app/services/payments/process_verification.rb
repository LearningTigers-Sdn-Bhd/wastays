# frozen_string_literal: true

require "ostruct"

module Payments
  class ProcessVerification
    attr_reader :quote, :gateway, :payment_response, :guest_details_from_params

    def initialize(quote:, gateway:, payment_response:, guest_details: {})
      @quote = quote
      @gateway = gateway
      @payment_response = payment_response
      @guest_details_from_params = guest_details
    end

    def call
      setting = quote.hotel.effective_payment_setting(gateway)
      if setting.blank? && gateway == "cute_mock"
        setting = OpenStruct.new(gateway: "cute_mock", api_key: "mock", secret_key: "mock")
      end

      return failure("Payment gateway is not configured.") unless setting

      adapter = Payments::GatewayRegistry.fetch(gateway: gateway, setting: setting)
      verification = adapter.verify_client_callback(payment_response: payment_response)

      guest_details = resolve_guest_details(verification[:metadata] || {})

      if verification[:status] == "captured"
        return failure("Missing guest details for booking confirmation.") if guest_details.blank?

        result = confirm_booking(quote, guest_details, verification[:external_reference])

        record_transaction(verification, result.booking)

        if result.success? && result.booking
          success(booking: result.booking)
        else
          failure(result.message.presence || "Payment verification passed, but booking confirmation failed.")
        end
      else
        record_transaction(verification)
        failure(verification[:message].presence || "Payment verification failed.")
      end
    rescue Payments::GatewayRegistry::UnsupportedGatewayError => e
      failure(e.message)
    rescue StandardError => e
      Rails.logger.error("Payment verification error: #{e.message}")
      failure("Unable to verify payment at the moment.")
    end

    private

    def resolve_guest_details(metadata)
      return guest_details_from_params if guest_details_from_params.present?

      metadata = metadata.to_h.symbolize_keys
      return if metadata.blank?

      {
        name: metadata[:guest_name] || metadata[:name],
        email: metadata[:guest_email] || metadata[:email],
        phone: metadata[:guest_phone] || metadata[:phone],
        government_id: metadata[:government_id],
        gender: metadata[:gender],
        city: metadata[:guest_city] || metadata[:city],
        country: metadata[:country],
        document_type: metadata[:document_type],
        marketing_consent: metadata[:marketing_consent],
        privacy_consent: metadata[:privacy_consent],
        special_requests: metadata[:special_requests]
      }.compact
    end

    def confirm_booking(quote, guest_details, external_reference)
      BookingEngine::ConfirmBooking.new(
        quote_token: quote.token,
        payment_details: {
          guest_name: guest_details[:name],
          guest_email: guest_details[:email],
          guest_phone: guest_details[:phone],
          government_id: guest_details[:government_id],
          gender: guest_details[:gender],
          guest_city: guest_details[:city],
          country: guest_details[:country],
          document_type: guest_details[:document_type],
          marketing_consent: guest_details[:marketing_consent],
          privacy_consent: guest_details[:privacy_consent],
          special_requests: guest_details[:special_requests],
          external_reference: external_reference
        }
      ).call
    end

    def record_transaction(verification, booking = nil)
      Payments::TransactionRecorder.record_verification(
        quote: quote,
        gateway: gateway,
        payment_response: payment_response,
        verification_result: verification,
        booking: booking
      )
    rescue StandardError => e
      Rails.logger.error("Payment transaction logging failed: #{e.message}")
    end

    def success(booking:)
      OpenStruct.new(success?: true, booking: booking)
    end

    def failure(message)
      OpenStruct.new(success?: false, error: message)
    end
  end
end
