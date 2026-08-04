# frozen_string_literal: true

require "digest"

module ExtraCharges
  class Quote
    Result = ApplicationResult.define(:amount, :calculated_amount, :base_amount, :quantity, :fingerprint, :metadata)

    def self.call(extra_charge:, folio:, booking:, requested_amount: nil, quantity: nil, expected_fingerprint: nil, preview: false)
      new(
        extra_charge:, folio:, booking:, requested_amount:, quantity:,
        expected_fingerprint:, preview:
      ).call
    end

    def initialize(extra_charge:, folio:, booking:, requested_amount:, quantity:, expected_fingerprint:, preview:)
      @extra_charge = extra_charge
      @folio = folio
      @booking = booking
      @requested_amount = requested_amount
      @requested_quantity = quantity
      @expected_fingerprint = expected_fingerprint.to_s
      @preview = preview
    end

    def call
      return Result.failure("Extra charge is not available.") unless available?

      case @extra_charge.pricing_type
      when "manual" then manual_quote
      when "fixed" then fixed_quote
      when "percentage" then percentage_quote
      else Result.failure("Extra charge pricing is not valid.")
      end
    end

    private

    def available?
      @extra_charge.hotel_id == @folio.hotel_id &&
        @extra_charge.transaction_code.kind == "charge" &&
        @extra_charge.transaction_code.active?
    end

    def manual_quote
      amount = @requested_amount.to_d
      return success(amount: nil, calculated_amount: nil, quantity: 1.to_d) if @preview
      return Result.failure("Amount must be greater than zero.") unless amount.positive?

      success(amount:, calculated_amount: amount, quantity: 1.to_d)
    end

    def fixed_quote
      quantity = calculated_quantity
      calculated_amount = money(@extra_charge.rate_value.to_d * quantity)
      requested_amount = @requested_amount.to_d
      amount = if @extra_charge.allow_amount_override? && requested_amount.positive?
        requested_amount
      else
        calculated_amount
      end

      success(amount:, calculated_amount:, quantity:)
    end

    def percentage_quote
      transactions = percentage_base_transactions
      base_amount = money(transactions.sum(&:amount))
      fingerprint = percentage_fingerprint(transactions)
      calculated_amount = money(base_amount * @extra_charge.rate_value.to_d / 100)

      if !@preview && (@expected_fingerprint.blank? || @expected_fingerprint != fingerprint)
        return Result.failure(
          "Folio charges changed. Review the updated percentage amount before posting.",
          amount: calculated_amount,
          calculated_amount:,
          base_amount:,
          quantity: 1.to_d,
          fingerprint:,
          metadata: metadata(calculated_amount:, base_amount:, quantity: 1.to_d)
        )
      end
      return Result.failure("No eligible charges are available for this percentage calculation.") unless base_amount.positive? || @preview

      success(
        amount: calculated_amount,
        calculated_amount:,
        base_amount:,
        quantity: 1.to_d,
        fingerprint:
      )
    end

    def calculated_quantity
      nights = [ (@booking.check_out.to_date - @booking.check_in.to_date).to_i, 1 ].max
      rooms = [ @booking.booking_rooms.count, 1 ].max
      people = [ @booking.adults.to_i + @booking.children.to_i, 1 ].max

      case @extra_charge.charging_unit
      when "per_item" then [ @requested_quantity.to_d, 1.to_d ].max
      when "per_stay" then 1.to_d
      when "per_night" then nights.to_d
      when "per_room" then rooms.to_d
      when "per_room_night" then (rooms * nights).to_d
      when "per_person" then people.to_d
      when "per_person_night" then (people * nights).to_d
      else 1.to_d
      end
    end

    def percentage_base_transactions
      scope = @folio.folio_transactions
        .where(transaction_type: "charge", voided_by_transaction_id: nil, reversal_of_transaction_id: nil)
        .where("amount > 0")
        .where.not(category: "tax")

      if @extra_charge.percentage_basis == "room_charges"
        scope = scope.where(category: "accommodation")
      else
        scope = scope.where("COALESCE(metadata ->> 'extra_charge_pricing_type', '') <> 'percentage'")
      end

      scope.order(:id).to_a
    end

    def percentage_fingerprint(transactions)
      Digest::SHA256.hexdigest(
        transactions.map { |transaction| "#{transaction.id}:#{transaction.amount.to_d.to_s('F')}" }.join("|")
      )
    end

    def success(amount:, calculated_amount:, quantity:, base_amount: nil, fingerprint: nil)
      Result.success(
        amount:,
        calculated_amount:,
        base_amount:,
        quantity:,
        fingerprint:,
        metadata: metadata(calculated_amount:, base_amount:, quantity:)
      )
    end

    def metadata(calculated_amount:, base_amount:, quantity:)
      {
        extra_charge_id: @extra_charge.id,
        extra_charge_pricing_type: @extra_charge.pricing_type,
        extra_charge_rate_value: @extra_charge.rate_value&.to_d&.to_s("F"),
        extra_charge_charging_unit: @extra_charge.charging_unit,
        extra_charge_quantity: quantity.to_d.to_s("F"),
        extra_charge_percentage_basis: @extra_charge.percentage_basis,
        extra_charge_base_amount: base_amount&.to_d&.to_s("F"),
        extra_charge_calculated_amount: calculated_amount&.to_d&.to_s("F"),
        extra_charge_amount_override: override_amount(calculated_amount)
      }.compact
    end

    def override_amount(calculated_amount)
      return if calculated_amount.blank? || @requested_amount.blank?
      return if @requested_amount.to_d == calculated_amount.to_d

      @requested_amount.to_d.to_s("F")
    end

    def money(value)
      value.to_d.round(2)
    end
  end
end
