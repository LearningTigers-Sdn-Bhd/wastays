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
        "no_show_penalty" => { code: "4030", desc: "No-Show Penalty Revenue" },
        "late_checkout_penalty" => { code: "4031", desc: "Late Checkout Penalty Revenue" },
        "early_departure_penalty" => { code: "4032", desc: "Early Departure Penalty Revenue" },
        "other" => { code: "4090", desc: "Other Revenue" },
        "gateway_payment" => { code: "1010", desc: "Bank - Gateway" },
        "cash" => { code: "1020", desc: "Bank - Cash" },
        "refund" => { code: "1030", desc: "Bank - Refunds" },
        "booking_payment" => { code: "2020", desc: "Booking Payment Liability" },
        "security_deposits" => { code: "2030", desc: "Security Deposit Liability" },
        "adjustment" => { code: "5010", desc: "Adjustments" },
        "correction" => { code: "5020", desc: "Corrections" },
        "discount" => { code: "5030", desc: "Discounts" },
        "write_off" => { code: "5040", desc: "Write-Offs" }
      }

      missing_categories = FolioTransaction.gl_mappable_categories - mappings.keys
      raise KeyError, "Missing default GL mappings for: #{missing_categories.join(', ')}" if missing_categories.any?

      mappings.each do |category, data|
        ensure_mapping!(category, data)
      end
    end

    private

    def ensure_mapping!(category, data)
      @hotel.hotel_general_ledger_maps.find_by(transaction_category: category) ||
        @hotel.hotel_general_ledger_maps.create!(
          transaction_category: category,
          gl_code: data[:code],
          description: data[:desc]
        )
    rescue ActiveRecord::RecordNotUnique
      @hotel.hotel_general_ledger_maps.find_by!(transaction_category: category)
    end
  end
end
