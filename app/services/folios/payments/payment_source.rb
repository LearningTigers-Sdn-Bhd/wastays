# frozen_string_literal: true

module Folios
  module Payments
    class PaymentSource
      SOURCES = {
        "cash" => {
          label: "Cash",
          display_label: "Cash",
          system_key: "cash_payment",
          reference_key: "receipt_reference",
          reference_prefix: "Receipt",
          reversible: true
        },
        "bank" => {
          label: "Bank Transfer",
          display_label: "Bank transfer",
          system_key: "bank_payment",
          reference_key: "bank_reference",
          reference_prefix: "Bank Ref",
          reversible: true
        },
        "card" => {
          label: "Card Terminal",
          display_label: "Card terminal",
          system_key: "card_payment",
          reference_key: "card_reference",
          reference_prefix: "Card Ref",
          reversible: true
        },
        "gateway" => {
          label: "Gateway Manual Recovery",
          display_label: "Manual recovery",
          system_key: "gateway_manual_recovery_payment",
          reference_key: "gateway_reference",
          reference_prefix: "Gateway Ref",
          required_reference: true,
          manual_recovery: true,
          reversible: false
        },
        "ota" => {
          label: "OTA Collected",
          display_label: "OTA collected",
          system_key: "ota_collected_payment",
          reference_key: "ota_reference",
          reference_prefix: "OTA Ref",
          required_reference: true,
          reversible: false
        }
      }.freeze

      attr_reader :key

      def self.options
        SOURCES.map { |key, config| [ config.fetch(:label), key ] }
      end

      def self.valid?(key)
        SOURCES.key?(key.to_s)
      end

      def self.fetch(key)
        return unless valid?(key)

        new(key)
      end

      def initialize(key)
        @key = key.to_s
      end

      def label
        config.fetch(:label)
      end

      def display_label
        config.fetch(:display_label)
      end

      def system_key
        config.fetch(:system_key)
      end

      def reference_key
        config.fetch(:reference_key)
      end

      def reference_prefix
        config.fetch(:reference_prefix)
      end

      def required_reference?
        !!config[:required_reference]
      end

      def manual_recovery?
        !!config[:manual_recovery]
      end

      def reversible?
        !!config[:reversible]
      end

      def transaction_code_for(hotel)
        TransactionCodes::Resolver.for(hotel).for_key(system_key)
      end

      private

      def config
        SOURCES.fetch(key)
      end
    end
  end
end
