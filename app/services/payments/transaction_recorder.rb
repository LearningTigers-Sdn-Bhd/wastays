module Payments
  class TransactionRecorder
    def self.record_checkout_session(quote:, gateway:, checkout_payload:)
      attrs = {
        booking_quote: quote,
        gateway: gateway,
        gateway_order_id: checkout_payload[:order_id] || checkout_payload["order_id"],
        status: "checkout_initiated",
        amount_subunits: checkout_payload[:amount] || checkout_payload["amount"],
        currency: checkout_payload[:currency] || checkout_payload["currency"],
        event_source: "checkout_session",
        gateway_payload: checkout_payload
      }

      upsert(attrs)
    end

    def self.record_verification(quote:, gateway:, payment_response:, verification_result:, booking: nil)
      status = verification_result[:status].to_s
      attrs = {
        booking_quote: quote,
        booking: booking,
        gateway: gateway,
        gateway_order_id: payment_response[:razorpay_order_id],
        external_reference: verification_result[:external_reference],
        signature: payment_response[:razorpay_signature],
        status: normalize_status(status),
        payment_method: verification_result[:payment_method],
        amount_subunits: verification_result[:amount],
        currency: verification_result[:currency],
        event_source: "client_callback",
        metadata: verification_result[:metadata] || {},
        gateway_payload: verification_result
      }
      attrs[:verified_at] = Time.current if status.in?(%w[captured authorized failed])
      attrs[:captured_at] = Time.current if status == "captured"
      attrs[:error_message] = verification_result[:message] if verification_result[:message].present?

      upsert(attrs)
    end

    def self.record_webhook(quote:, gateway:, webhook_payload:, processed_payload:, booking: nil, status: nil)
      resolved_status = normalize_status(status.presence || processed_payload[:status])
      attrs = {
        booking_quote: quote,
        booking: booking,
        gateway: gateway,
        external_reference: processed_payload[:external_reference],
        gateway_order_id: processed_payload[:gateway_order_id],
        status: resolved_status,
        payment_method: processed_payload[:payment_method],
        amount_subunits: processed_payload[:amount],
        currency: processed_payload[:currency],
        event_source: "webhook",
        metadata: processed_payload[:metadata] || {},
        gateway_payload: webhook_payload
      }
      attrs[:verified_at] = Time.current
      attrs[:captured_at] = Time.current if resolved_status == "captured"

      upsert(attrs)
    end

    def self.upsert(attrs)
      transaction = find_existing(attrs) || PaymentTransaction.new
      transaction.assign_attributes(attrs.compact)
      transaction.save!
      stamp_booking_collector!(transaction)

      if transaction.captured_at.present? && transaction.booking.present? && transaction.booking.booking_folio.present?
        Folios::RecordPaymentFromGateway.call(transaction)
      end

      transaction
    end
    private_class_method :upsert

    def self.find_existing(attrs)
      gateway = attrs[:gateway]
      external_reference = attrs[:external_reference]
      gateway_order_id = attrs[:gateway_order_id]

      if external_reference.present?
        transaction = PaymentTransaction.find_by(gateway: gateway, external_reference: external_reference)
        return transaction if transaction

        return unless gateway_order_id.present?

        PaymentTransaction.find_by(gateway: gateway, gateway_order_id: gateway_order_id)
      elsif gateway_order_id.present?
        PaymentTransaction.find_by(gateway: gateway, gateway_order_id: gateway_order_id)
      end
    end
    private_class_method :find_existing

    def self.normalize_status(status)
      normalized = status.to_s
      return "captured" if normalized == "captured"
      return "authorized" if normalized == "authorized"
      return "failed" if normalized == "failed"

      "pending"
    end
    private_class_method :normalize_status

    def self.stamp_booking_collector!(transaction)
      booking = transaction.booking
      return unless booking
      return unless transaction.captured_at.present? || transaction.status == "captured"
      return unless transaction.wastays_collected_payment?
      return if booking.fund_collector == "wastays"

      booking.update!(fund_collector: "wastays")
    end
    private_class_method :stamp_booking_collector!
  end
end
