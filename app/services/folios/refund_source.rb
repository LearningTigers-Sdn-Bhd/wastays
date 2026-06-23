# frozen_string_literal: true

module Folios
  class RefundSource
    SOURCES = {
      "cash" => {
        label: "Cash",
        display_label: "Cash"
      },
      "bank_transfer" => {
        label: "Bank Transfer",
        display_label: "Bank transfer"
      },
      "card_terminal" => {
        label: "Card Terminal",
        display_label: "Card terminal"
      },
      "gateway" => {
        label: "Gateway",
        display_label: "Gateway"
      },
      "ota_reconciliation" => {
        label: "OTA Reconciliation",
        display_label: "OTA reconciliation"
      },
      "manual_adjustment" => {
        label: "Manual Adjustment",
        display_label: "Manual adjustment"
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

    private

    def config
      SOURCES.fetch(key)
    end
  end
end
