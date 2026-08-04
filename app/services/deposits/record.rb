# frozen_string_literal: true

module Deposits
  class Record
    def self.call(owner:, kind:, amount:, currency:, payment_method:, actor: nil, external_reference: nil,
      hotel_corporate_account: nil, metadata: {}, status: nil, received_at: nil, operation_key: nil,
      hotel_payment_method_id: nil)
      new(owner:, kind:, amount:, currency:, payment_method:, actor:, external_reference:,
        hotel_corporate_account:, metadata:, status:, received_at:, operation_key:, hotel_payment_method_id:).call
    end

    def initialize(owner:, kind:, amount:, currency:, payment_method:, actor:, external_reference:,
      hotel_corporate_account:, metadata:, status:, received_at:, operation_key:, hotel_payment_method_id: nil)
      @owner = owner
      @kind = kind.to_s
      @amount = amount.to_d
      @currency = currency.to_s.presence || owner.hotel.default_currency || "MYR"
      @payment_method = payment_method.to_s.presence || "cash"
      @actor = actor
      @external_reference = external_reference.to_s.strip.presence
      @hotel_corporate_account = hotel_corporate_account
      @metadata = metadata.to_h
      @status = status.to_s.presence
      @received_at = received_at
      @operation_key = operation_key.to_s.presence
      @hotel_payment_method_id = hotel_payment_method_id
      @hotel_payment_method = nil
    end

    def call
      unless @amount.positive?
        message = @kind == "security" ? "Security deposit amount must be greater than zero." : "Deposit amount must be positive."
        return failure(message)
      end
      return failure("Unknown deposit kind.") unless @kind.in?(Deposit::KINDS)
      return failure("Deposit owner must be a booking or group booking.") unless @owner.is_a?(Booking) || @owner.is_a?(GroupBooking)
      method_error = resolve_hotel_payment_method
      return failure(method_error) if method_error.present?
      existing = existing_deposit
      return success(existing) if matching_retry?(existing)

      deposit = nil
      Deposit.transaction do
        deposit = Deposit.create!(deposit_attributes)
        deposit.deposit_movements.create!(
          movement_type: @kind == "security" ? "hold" : "receive",
          amount: @amount,
          payment_method: resolved_payment_method,
          external_reference: @external_reference,
          performed_by: @actor,
          occurred_at: deposit.received_at,
          operation_key: @operation_key || "deposit:#{deposit.id}:opening",
          metadata: configured_metadata
        )
        sync_booking_deposit_status!(deposit)
      end
      success(deposit)
    rescue ActiveRecord::RecordInvalid => e
      existing = existing_deposit
      return success(existing) if matching_retry?(existing)

      failure(e.record.errors.full_messages.to_sentence)
    rescue ActiveRecord::RecordNotUnique
      existing = existing_deposit
      return success(existing) if matching_retry?(existing)

      failure("Deposit reference has already been used.")
    end

    private

    def existing_deposit
      if @operation_key
        movement = DepositMovement.find_by(operation_key: @operation_key)
        opening_type = @kind == "security" ? "hold" : "receive"
        movement.deposit if movement&.movement_type == opening_type && movement.amount == @amount
      elsif @external_reference
        Deposit.find_by(
          hotel: hotel,
          booking: (@owner if @owner.is_a?(Booking)),
          group_booking: (@owner if @owner.is_a?(GroupBooking)),
          external_reference: @external_reference
        )
      end
    end

    def hotel
      @owner.hotel
    end

    def deposit_attributes
      {
        hotel: hotel,
        booking: (@owner if @owner.is_a?(Booking)),
        group_booking: (@owner if @owner.is_a?(GroupBooking)),
        hotel_corporate_account: @hotel_corporate_account,
        transaction_code: transaction_code,
        received_by: @actor,
        kind: @kind,
        status: @status || (@kind == "security" ? "held" : "available"),
        amount: @amount,
        currency: @currency,
        payment_method: resolved_payment_method,
        external_reference: @external_reference,
        received_at: @received_at || Time.current,
        metadata: configured_metadata
      }
    end

    def transaction_code
      Financials::EnsureDefaultTransactionCodes.call(hotel)
      return @hotel_payment_method.transaction_code if @kind == "prepayment" && @hotel_payment_method.present?

      key = @kind == "security" ? "security_deposit" : "bank_payment"
      TransactionCodes::Resolver.for(hotel).for_key!(key)
    end

    def resolve_hotel_payment_method
      return unless @hotel_payment_method_id.present?

      purpose = @kind == "prepayment" ? :guest_advance : :direct
      result = PaymentMethods::Eligibility.call(hotel:, id: @hotel_payment_method_id, purpose:)
      @hotel_payment_method = result.payment_method if result.success?
      result.error unless result.success?
    end

    def resolved_payment_method
      return @payment_method unless @hotel_payment_method.present?

      case @hotel_payment_method.transaction_code.system_key
      when "cash_payment" then "cash"
      when "card_payment" then "card"
      when "bank_payment" then "bank_transfer"
      when "gateway_manual_recovery_payment" then "manual"
      else @hotel_payment_method.cash? ? "cash" : "manual"
      end
    end

    def configured_metadata
      return @metadata unless @hotel_payment_method.present?

      @metadata.merge(
        hotel_payment_method_id: @hotel_payment_method.id,
        payment_method_name: @hotel_payment_method.name,
        payment_method_code: @hotel_payment_method.code,
        payment_method_type: @hotel_payment_method.payment_method_type
      )
    end

    def sync_booking_deposit_status!(deposit)
      return unless deposit.kind_security? && deposit.booking.present?

      Deposits::SyncBookingDepositStatus.call(deposit.booking)
    end

    def matching_retry?(deposit)
      deposit.present? && deposit.owner == @owner && deposit.kind == @kind &&
        deposit.amount == @amount && deposit.currency == @currency
    end

    def success(deposit)
      Deposits::RecordResult.success(deposit: deposit)
    end

    def failure(message)
      Deposits::RecordResult.failure(message)
    end
  end
end
