# frozen_string_literal: true

module PaymentMethods
  class EnsureDefaults
    CASH_SYSTEM_KEYS = %w[cash_payment cash_prepayment].freeze
    SYSTEM_KEYS = %w[cash_payment cash_prepayment card_payment card_prepayment bank_payment gateway_manual_recovery_payment ota_collected_payment].freeze

    def self.call(hotel)
      new(hotel).call
    end

    def initialize(hotel)
      @hotel = hotel
    end

    def call
      Financials::EnsureDefaultTransactionCodes.call(@hotel)
      existing_ids = @hotel.hotel_payment_methods.pluck(:transaction_code_id).to_set
      next_position = @hotel.hotel_payment_methods.maximum(:position).to_i + 1

      @hotel.transaction_codes.where(system_key: SYSTEM_KEYS).order(:id).find_each do |code|
        next if existing_ids.include?(code.id)

        @hotel.hotel_payment_methods.create!(
          transaction_code: code,
          payment_method_type: CASH_SYSTEM_KEYS.include?(code.system_key) ? "cash" : "bank_gateway",
          default_cash: code.system_key == "cash_payment" && !@hotel.hotel_payment_methods.where(default_cash: true).exists?,
          guest_advance: code.category == "booking_payment",
          position: next_position
        )
        next_position += 1
      end
    end
  end
end
