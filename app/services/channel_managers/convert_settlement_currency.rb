# frozen_string_literal: true

module ChannelManagers
  # Converts a persisted settlement amount for folio posting without mutating
  # either the settlement or its source-currency allocation.
  class ConvertSettlementCurrency
    Result = ApplicationResult.define(:amount, :rate, :source, :source_currency, :target_currency, :rounding_amount)

    def self.call(amount:, settlement:, target_currency:)
      new(amount:, settlement:, target_currency:).call
    end

    def initialize(amount:, settlement:, target_currency:)
      @amount = amount.to_d
      @settlement = settlement
      @source_currency = CurrencyCatalog.normalize(settlement.currency, fallback: nil)
      @target_currency = CurrencyCatalog.normalize(target_currency, fallback: nil)
    end

    def call
      return Result.failure("Settlement and folio currencies are required") if @source_currency.blank? || @target_currency.blank?

      conversion = CurrencyConverter.convert(
        @amount,
        from: @source_currency,
        to: @target_currency,
        hotel: @settlement.hotel
      )
      return Result.failure("Missing exchange rate from #{@source_currency} to #{@target_currency}") if conversion.blank?

      rounded_amount = conversion.amount.round(CurrencyCatalog.precision_for(@target_currency))
      Result.success(
        amount: rounded_amount,
        rate: conversion.rate,
        source: conversion.source,
        source_currency: @source_currency,
        target_currency: @target_currency,
        rounding_amount: rounded_amount - conversion.amount
      )
    rescue ArgumentError => e
      Result.failure(e.message)
    end
  end
end
