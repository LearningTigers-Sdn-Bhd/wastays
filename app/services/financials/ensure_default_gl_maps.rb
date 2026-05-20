# frozen_string_literal: true

module Financials
  class EnsureDefaultGlMaps
    def self.call(hotel)
      new(hotel).call
    end

    def initialize(hotel)
      @hotel = hotel
    end

    def call
      mappings = {
        "accommodation" => { code: "4010", desc: "Room Revenue" },
        "tax" => { code: "2010", desc: "Tax Liabilities" },
        "fb" => { code: "4020", desc: "Food & Beverage Revenue" },
        "gateway_payment" => { code: "1010", desc: "Bank - Gateway" },
        "cash" => { code: "1020", desc: "Bank - Cash" },
        "refund" => { code: "1030", desc: "Bank - Refunds" },
        "adjustment" => { code: "5010", desc: "Adjustments & Write-offs" }
      }

      mappings.each do |category, data|
        @hotel.hotel_general_ledger_maps.find_or_create_by!(
          transaction_category: category
        ) do |map|
          map.gl_code = data[:code]
          map.description = data[:desc]
        end
      end
    end
  end
end
