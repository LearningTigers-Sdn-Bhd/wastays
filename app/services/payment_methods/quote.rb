# frozen_string_literal: true

module PaymentMethods
  class Quote
    Result = ApplicationResult.define(:payment_method, :base_amount, :surcharge_amount, :surcharge_tax_total, :collected_total)

    def self.call(hotel:, payment_method_id:, base_amount:, purpose: :guest_advance, booking: nil)
      new(hotel:, payment_method_id:, base_amount:, purpose:, booking:).call
    end

    def initialize(hotel:, payment_method_id:, base_amount:, purpose:, booking: nil)
      @hotel = hotel
      @payment_method_id = payment_method_id
      @base_amount = base_amount.to_d.round(2)
      @purpose = purpose
      @booking = booking
    end

    def call
      method_result = PaymentMethods::Eligibility.call(
        hotel: @hotel, id: @payment_method_id, purpose: @purpose
      )
      return Result.failure(method_result.error) unless method_result.success?

      method = method_result.payment_method
      surcharge_amount = method.surcharge_amount(@base_amount)
      if surcharge_amount.positive? && (method.surcharge_extra_charge.blank? || !method.surcharge_extra_charge.active?)
        return Result.failure("Payment surcharge is not available.")
      end

      surcharge_tax_total = tax_rules(method).sum { |rule| rule.compute(surcharge_amount) }.to_d.round(2)
      collected_total = (@base_amount + surcharge_amount + surcharge_tax_total).round(2)

      Result.success(
        payment_method: method,
        base_amount: @base_amount,
        surcharge_amount: surcharge_amount,
        surcharge_tax_total: surcharge_tax_total,
        collected_total: collected_total
      )
    end

    private

    def tax_rules(method)
      transaction_code = method.surcharge_extra_charge&.transaction_code
      return [] unless transaction_code

      rules = if @booking
        Folios::Routing::EffectiveTaxRules.call(booking: @booking, transaction_code: transaction_code)
      else
        transaction_code.transaction_code_taxes.includes(:hotel_tax)
      end
      rules.select(&:enabled_for_posting?)
    end
  end
end
