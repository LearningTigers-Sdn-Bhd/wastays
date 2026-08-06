# frozen_string_literal: true

module FinancialControls
  class AuditEventRecorder
    def self.call!(**kwargs)
      new(**kwargs).call!
    end

    def initialize(hotel:, business_date:, event_type:, source:, actor: nil, amount: nil, currency: nil,
      folio_transaction: nil, booking_folio: nil, booking: nil, payment_transaction: nil,
      refund_request: nil, night_audit: nil, hotel_business_date: nil, reason: nil, metadata: {})
      @hotel = hotel
      @business_date = business_date.to_date
      @event_type = event_type.to_s
      @source = source.to_s
      @actor = actor
      @amount = amount
      @currency = currency
      @folio_transaction = folio_transaction
      @booking_folio = booking_folio
      @booking = booking
      @payment_transaction = payment_transaction
      @refund_request = refund_request
      @night_audit = night_audit
      @hotel_business_date = hotel_business_date
      @reason = reason.presence
      @metadata = metadata || {}
    end

    def call!
      FinancialAuditEvent.create!(attributes)
    end

    private

    def attributes
      {
        hotel: @hotel,
        business_date: @business_date,
        event_type: @event_type,
        actor: @actor,
        source: @source,
        amount: amount,
        currency: currency,
        folio_transaction: @folio_transaction,
        booking_folio: booking_folio,
        booking: booking,
        payment_transaction_id: payment_transaction_id,
        refund_request_id: refund_request_id,
        night_audit_id: night_audit_id,
        hotel_business_date: @hotel_business_date,
        reason: @reason,
        metadata: normalized_metadata,
        request_id: Current.request_id,
        occurred_at: Time.current
      }
    end

    def booking_folio
      @booking_folio || @folio_transaction&.booking_folio
    end

    def booking
      @booking || booking_folio&.booking || @payment_transaction&.booking || @refund_request&.booking
    end

    def amount
      @amount.nil? ? @folio_transaction&.amount : @amount
    end

    def currency
      @currency || @folio_transaction&.currency || booking&.currency
    end

    def payment_transaction_id
      @payment_transaction&.id || metadata_id("payment_transaction_id")
    end

    def refund_request_id
      @refund_request&.id || metadata_id("refund_request_id")
    end

    def night_audit_id
      @night_audit&.id || metadata_id("night_audit_id") || normalized_metadata.dig("blocker_resolution", "night_audit_id")
    end

    def metadata_id(key)
      value = normalized_metadata[key]
      value.presence
    end

    def normalized_metadata
      @normalized_metadata ||= @metadata.deep_stringify_keys
    end
  end
end
