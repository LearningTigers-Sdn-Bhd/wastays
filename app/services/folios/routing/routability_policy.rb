# frozen_string_literal: true

module Folios
  module Routing
    class RoutabilityPolicy
      def self.parent_codes(hotel:)
        new(hotel:).parent_codes
      end

      def initialize(hotel:)
        @hotel = hotel
      end

      def parent_codes
        @hotel.transaction_codes.active.charge
          .includes(transaction_code_taxes: { hotel_tax: :transaction_code })
          .where.not(id: generated_code_ids)
          .order(:code)
      end

      private

      def generated_code_ids
        custom = @hotel.hotel_taxes.where.not(transaction_code_id: nil).select(:transaction_code_id)
        primary = @hotel.transaction_codes.where(system_key: TransactionCodeTax::PRIMARY_TAX_KEYS).select(:id)
        @hotel.transaction_codes.where(id: custom).or(@hotel.transaction_codes.where(id: primary)).select(:id)
      end
    end
  end
end
