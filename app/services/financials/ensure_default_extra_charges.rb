# frozen_string_literal: true

module Financials
  class EnsureDefaultExtraCharges
    SYSTEM_KEYS = %w[fnb_revenue parking_revenue damage_revenue cleaning_revenue misc_revenue].freeze

    def self.call(hotel)
      new(hotel).call
    end

    def initialize(hotel)
      @hotel = hotel
    end

    def call
      EnsureDefaultTransactionCodes.call(@hotel)
      existing_ids = @hotel.hotel_extra_charges.pluck(:transaction_code_id).to_set
      next_position = @hotel.hotel_extra_charges.maximum(:position).to_i + 1

      @hotel.transaction_codes.where(system_key: SYSTEM_KEYS).order(:id).find_each do |transaction_code|
        next if existing_ids.include?(transaction_code.id)

        @hotel.hotel_extra_charges.create!(
          transaction_code: transaction_code,
          pricing_type: "manual",
          charging_unit: "per_item",
          allow_amount_override: true,
          position: next_position
        )
        next_position += 1
      end
    end
  end
end
