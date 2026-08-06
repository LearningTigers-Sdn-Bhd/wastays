# frozen_string_literal: true

module ReservationPolicies
  # Gives every hotel the four stay-event policies, seeded to reproduce exactly
  # what the code did before they existed: no-show bills one night, late checkout
  # and early departure wait for staff to name an amount, and cancellation charges
  # nothing at all. Configuring a policy is therefore opt-in — creating the rows
  # changes no behaviour on its own.
  class EnsureDefaults
    DEFAULTS = [
      { policy_type: "no_show", system_key: "no_show_revenue", active: true, pricing_type: "nights", rate_value: 1, allow_amount_override: false },
      { policy_type: "late_checkout", system_key: "late_checkout_revenue", active: true, pricing_type: "manual", rate_value: nil, allow_amount_override: true },
      { policy_type: "early_departure", system_key: "early_departure_revenue", active: true, pricing_type: "manual", rate_value: nil, allow_amount_override: true },
      { policy_type: "cancellation", system_key: "cancel_revenue", active: false, pricing_type: "manual", rate_value: nil, allow_amount_override: true }
    ].freeze

    def self.call(hotel) = new(hotel).call

    def initialize(hotel)
      @hotel = hotel
    end

    def call
      Financials::EnsureDefaultTransactionCodes.call(@hotel)
      existing = @hotel.hotel_reservation_policies.pluck(:policy_type).to_set

      DEFAULTS.each_with_index do |default, index|
        next if existing.include?(default[:policy_type])

        transaction_code = @hotel.transaction_codes.find_by(system_key: default[:system_key])
        next if transaction_code.blank?

        @hotel.hotel_reservation_policies.create!(
          transaction_code: transaction_code,
          policy_type: default[:policy_type],
          active: default[:active],
          pricing_type: default[:pricing_type],
          rate_value: default[:rate_value],
          allow_amount_override: default[:allow_amount_override],
          position: index + 1
        )
      end

      @hotel.hotel_reservation_policies.reset
    end
  end
end
