# frozen_string_literal: true

require "ostruct"

module CorporateArPayments
  class CaptureIntent
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(intent:, gateway:, payment_response: {}, verification_result:, event_source:)
      @intent = intent
      @gateway = gateway
      @payment_response = payment_response.to_h.symbolize_keys
      @verification_result = verification_result.to_h.symbolize_keys
      @event_source = event_source
    end

    def call
      transaction = nil
      payment = nil

      ActiveRecord::Base.transaction do
        @intent.lock!

        if @intent.captured? && @intent.ar_payment.present?
          payment = @intent.ar_payment
          transaction = find_transaction
        elsif captured?
          payment = @intent.ar_payment || create_ar_payment!
          @intent.update!(captured_attributes(payment)) unless @intent.ar_payment_id == payment.id && @intent.captured?
          transaction = record_transaction!(payment)
        else
          @intent.update!(failed_attributes) unless @intent.captured?
          transaction = record_transaction!(nil) unless @intent.captured?
        end
      end

      captured? ? success(payment, transaction) : failure(@verification_result[:message].presence || capture_error || "Payment verification failed.", transaction)
    rescue ActiveRecord::RecordNotUnique
      @intent.reload
      success(@intent.ar_payment, PaymentTransaction.find_by(gateway: @gateway, external_reference: external_reference))
    rescue StandardError => e
      Rails.logger.error("Corporate AR capture error: #{e.message}")
      failure("Unable to record corporate AR payment.", nil)
    end

    private

    def captured?
      @verification_result[:status].to_s == "captured" && capture_error.blank?
    end

    def create_ar_payment!
      ArPayment.create!(
        hotel: @intent.hotel,
        hotel_corporate_account: @intent.hotel_corporate_account,
        amount: @intent.amount,
        currency: @intent.currency,
        reference_number: external_reference.presence || @intent.gateway_order_id,
        received_at: Date.current,
        payment_method: ar_payment_method,
        notes: "Corporate portal gateway payment",
        metadata: {
          source: "corporate_portal_gateway",
          corporate_ar_payment_intent_id: @intent.id,
          gateway: @gateway,
          gateway_order_id: gateway_order_id,
          external_reference: external_reference,
          payment_method: @verification_result[:payment_method],
          remittance_suggestions: @intent.remittance_suggestions,
          invoice_snapshots: @intent.invoice_snapshots
        }
      )
    end

    def ar_payment_method
      @verification_result[:payment_method].to_s == "card" ? "card" : "other"
    end

    def captured_attributes(payment)
      {
        ar_payment: payment,
        status: "captured",
        external_reference: external_reference,
        gateway_order_id: gateway_order_id,
        verified_at: Time.current,
        captured_at: Time.current,
        error_message: nil
      }
    end

    def failed_attributes
      {
        status: "failed",
        external_reference: external_reference,
        gateway_order_id: gateway_order_id,
        verified_at: Time.current,
        error_message: @verification_result[:message].presence || capture_error
      }
    end

    def record_transaction!(payment)
      find_transaction.tap do |transaction|
        transaction.assign_attributes(
          corporate_ar_payment_intent: @intent,
          ar_payment: payment,
          gateway: @gateway,
          gateway_order_id: gateway_order_id,
          external_reference: external_reference,
          signature: @payment_response[:razorpay_signature],
          status: captured? ? "captured" : "failed",
          payment_method: @verification_result[:payment_method],
          amount_subunits: @verification_result[:amount],
          currency: @verification_result[:currency] || @intent.currency,
          event_source: @event_source,
          metadata: @verification_result[:metadata] || {},
          gateway_payload: @verification_result
        )
        transaction.verified_at ||= Time.current
        transaction.captured_at ||= Time.current if captured?
        transaction.error_message = @verification_result[:message].presence || capture_error unless captured?
        transaction.save!
      end
    end

    def capture_error
      @capture_error ||= begin
        if @verification_result[:status].to_s != "captured"
          nil
        elsif @intent.gateway_order_id.present? && gateway_order_id.present? && gateway_order_id != @intent.gateway_order_id
          "Payment order does not match this AR payment request."
        elsif @verification_result[:currency].present? && @verification_result[:currency].to_s != @intent.currency
          "Payment currency does not match this AR payment request."
        elsif @verification_result[:amount].present? && @verification_result[:amount].to_i != expected_amount_subunits
          "Payment amount does not match this AR payment request."
        end
      end
    end

    def expected_amount_subunits
      case @intent.currency.to_s.upcase
      when "JPY"
        @intent.amount.to_i
      else
        (@intent.amount.to_d * 100).to_i
      end
    end

    def find_transaction
      if external_reference.present?
        PaymentTransaction.find_by(gateway: @gateway, external_reference: external_reference) ||
          PaymentTransaction.find_by(gateway: @gateway, gateway_order_id: gateway_order_id) ||
          PaymentTransaction.new
      else
        PaymentTransaction.find_by(gateway: @gateway, gateway_order_id: gateway_order_id) || PaymentTransaction.new
      end
    end

    def gateway_order_id
      @verification_result[:gateway_order_id].presence || @payment_response[:razorpay_order_id].presence || @intent.gateway_order_id
    end

    def external_reference
      @verification_result[:external_reference].presence || @payment_response[:razorpay_payment_id]
    end

    def success(payment, transaction)
      OpenStruct.new(success?: true, ar_payment: payment, transaction: transaction, error: nil)
    end

    def failure(error, transaction)
      OpenStruct.new(success?: false, ar_payment: nil, transaction: transaction, error: error)
    end
  end
end
