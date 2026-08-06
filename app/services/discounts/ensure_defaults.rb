# frozen_string_literal: true

module Discounts
  class EnsureDefaults
    def self.call(hotel)
      new(hotel).call
    end

    def initialize(hotel)
      @hotel = hotel
    end

    def call
      Financials::EnsureDefaultTransactionCodes.call(@hotel)
      existing_ids = @hotel.hotel_discounts.pluck(:transaction_code_id).to_set
      next_position = @hotel.hotel_discounts.maximum(:position).to_i + 1

      @hotel.transaction_codes.where(kind: "adjustment", category: "discount").order(:id).find_each do |code|
        next if existing_ids.include?(code.id)

        @hotel.hotel_discounts.create!(
          transaction_code: code, pricing_type: "manual", application_scope: "all_eligible_charges",
          allow_amount_override: true, position: next_position
        )
        next_position += 1
      end
    end
  end
end
