# frozen_string_literal: true

module Folios
  # The reference staff typed (or the gateway returned) for a payment or refund
  # posted to a folio, wherever the posting path happened to store it.
  #
  # Staff payments keep it under their payment source's key (bank_reference,
  # card_reference, ...), sometimes nested in source_references; check-in and
  # booking-time payments use a plain "reference"; older rows used
  # "payment_reference"; gateway payments keep only a payment_transaction_id and
  # the reference lives on PaymentTransaction#external_reference. Reports read
  # it through here so they cannot disagree about which key wins.
  class PaymentReference
    # Most specific first: a payment source's own key beats the generic ones.
    METADATA_KEYS = %w[
      receipt_reference bank_reference card_reference gateway_reference ota_reference
      reference payment_reference auth_code authorization_code gateway_payment_id
    ].freeze

    def self.value(transaction, payment_transaction: nil)
      new(transaction, payment_transaction:).value
    end

    # One query for every gateway row, so a report never looks references up
    # one transaction at a time.
    def self.by_transaction_id(transactions)
      transactions = Array(transactions)
      gateway_ids = transactions.filter_map { |transaction| payment_transaction_id(transaction) }.uniq
      payments = gateway_ids.any? ? PaymentTransaction.where(id: gateway_ids).index_by { |payment| payment.id.to_s } : {}

      transactions.to_h do |transaction|
        [ transaction.id, value(transaction, payment_transaction: payments[payment_transaction_id(transaction)]) ]
      end
    end

    def self.payment_transaction_id(transaction)
      transaction.metadata.to_h.stringify_keys["payment_transaction_id"].presence&.to_s
    end

    def initialize(transaction, payment_transaction: nil)
      @metadata = transaction.metadata.to_h.deep_stringify_keys
      @payment_transaction = payment_transaction
    end

    def value
      (source_reference || metadata_reference || gateway_reference)&.to_s&.strip.presence
    end

    private

    attr_reader :metadata

    def source_reference
      source = Folios::Payments::PaymentSource.fetch(metadata["payment_source"]) if metadata["payment_source"].present?
      return if source.blank?

      lookup(source.reference_key)
    end

    def metadata_reference
      METADATA_KEYS.lazy.filter_map { |key| lookup(key) }.first
    end

    def gateway_reference
      @payment_transaction&.external_reference.presence
    end

    def lookup(key)
      nested = metadata["source_references"]
      metadata[key].presence || (nested[key].presence if nested.is_a?(Hash))
    end
  end
end
