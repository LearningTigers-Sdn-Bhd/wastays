# frozen_string_literal: true

module PaymentMethods
  class Eligibility
    Result = ApplicationResult.define(:payment_method)
    PURPOSES = %i[guest_advance direct].freeze

    def self.call(hotel:, id: nil, purpose:)
      new(hotel:, id:, purpose:).call
    end

    def initialize(hotel:, id: nil, purpose:)
      @hotel = hotel
      @id = id
      @purpose = purpose.to_sym
    end

    def call
      return failure("Unknown payment method purpose.") unless PURPOSES.include?(@purpose)

      method = configured_method
      return failure(error_message) if method.blank?
      return failure(error_message) if @purpose == :guest_advance && !method.guest_advance?
      return failure(error_message) if @purpose == :direct && method.guest_advance?

      Result.success(payment_method: method)
    end

    private

    def configured_method
      PaymentMethods::EnsureDefaults.call(@hotel)
      @hotel.hotel_payment_methods
        .active
        .includes(:transaction_code, surcharge_extra_charge: { transaction_code: :transaction_code_taxes })
        .find_by(id: @id) if @id.present?
    end

    def error_message
      @purpose == :guest_advance ? "Select a valid guest advance payment method." : "Select a valid direct payment method."
    end

    def failure(message)
      Result.failure(message, payment_method: nil)
    end
  end
end
