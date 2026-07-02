# frozen_string_literal: true

require "ostruct"

module Deposits
  class RecordSecurityDeposit
    def self.call(booking:, folio:, user:, amount:, payment_method:, external_reference: nil)
      new(
        booking: booking,
        folio: folio,
        user: user,
        amount: amount,
        payment_method: payment_method,
        external_reference: external_reference
      ).call
    end

    def initialize(booking:, folio:, user:, amount:, payment_method:, external_reference: nil)
      @booking = booking
      @folio = folio
      @user = user
      @amount = amount.to_d
      @payment_method = payment_method.to_s.presence || "cash"
      @external_reference = external_reference.to_s.presence
    end

    def call
      return success(nil) unless @amount.positive?
      return failure("Booking must have a folio before recording a security deposit.") if @folio.blank?

      deposit = Deposit.create!(
        hotel: @booking.hotel,
        booking: @booking,
        booking_folio: @folio,
        transaction_code: security_deposit_transaction_code,
        user: @user,
        hold_type: "security",
        status: "held",
        amount: @amount,
        currency: @booking.currency || @booking.hotel.default_currency || "MYR",
        payment_method: @payment_method,
        external_reference: @external_reference,
        metadata: {
          source: "check_in",
          posted_by_user_id: @user&.id
        }
      )

      success(deposit)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    private

    def success(deposit)
      OpenStruct.new(success?: true, deposit: deposit)
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error)
    end

    def security_deposit_transaction_code
      Financials::EnsureDefaultTransactionCodes.call(@booking.hotel)
      @booking.hotel.transaction_codes.find_by!(system_key: "security_deposit")
    end
  end
end
