# frozen_string_literal: true

module Checkouts
  module PaymentMethods
    METHODS = {
      "cash" => {
        settlement_label: "Cash",
        release_label: "Cash returned",
        payment_source: "cash"
      },
      "card" => {
        settlement_label: "Card",
        release_label: "Card released",
        payment_source: "card"
      },
      "bank_transfer" => {
        settlement_label: "Bank transfer",
        release_label: "Bank transfer",
        payment_source: "bank"
      },
      "manual" => {
        settlement_label: "Manual recovery",
        release_label: "Other/manual",
        payment_source: "gateway"
      }
    }.freeze

    module_function

    def valid?(value)
      METHODS.key?(value.to_s)
    end

    def settlement_options
      options_for(:settlement_label)
    end

    def release_options
      options_for(:release_label)
    end

    def payment_source_for(value)
      METHODS.dig(value.to_s, :payment_source)
    end

    def options_for(label_key)
      METHODS.map { |value, config| [ config.fetch(label_key), value ] }
    end
    private_class_method :options_for
  end
end
