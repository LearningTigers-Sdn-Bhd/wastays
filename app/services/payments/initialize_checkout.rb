# frozen_string_literal: true

require "ostruct"

module Payments
  class InitializeCheckout
    include ActiveModel::Validations

    attr_reader :quote, :gateway, :guest_details, :callback_url

    validates :quote, :gateway, :callback_url, presence: true

    def initialize(quote:, callback_url:, gateway: nil, guest_details: {})
      @quote = quote
      @gateway = gateway || quote.hotel.checkout_payment_gateway || "mock"
      @guest_details = guest_details.to_h.symbolize_keys
      @callback_url = callback_url
    end

    def call
      return failure("Invalid parameters") unless valid?

      setting = quote.hotel.effective_payment_setting(gateway)
      return failure("Payment gateway is not configured.") unless setting

      adapter = Payments::GatewayRegistry.fetch(gateway: gateway, setting: setting)
      payload = adapter.create_checkout_session(
        amount: payable_total,
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

    def payable_total
      @payable_total ||= begin
        if quote.booking_quote_items.blank?
          quote.total_amount
        else
          snapshot = Bookings::BuildFinancialSnapshot.new(
            hotel: quote.hotel,
            check_in: quote.check_in,
            check_out: quote.check_out,
            guest_country: normalize_country(guest_details[:country]),
            room_items: quote.booking_quote_items.map do |item|
              {
                quantity: item.quantity,
                nightly_rate_snapshot: item.nightly_rate_snapshot
              }
            end
          ).call

          snapshot.room_total + snapshot.tax_total
        end
      end
    end

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

    def normalize_country(value)
      return if value.blank?

      country = ISO3166::Country.find_country_by_any_name(value.to_s.strip)
      country&.iso_short_name || value.to_s.split.map(&:capitalize).join(" ")
    rescue StandardError
      value.to_s.split.map(&:capitalize).join(" ")
    end

    def success(payload)
      OpenStruct.new(success?: true, payload: payload)
    end

    def failure(message)
      OpenStruct.new(success?: false, error: message)
    end
  end
end
