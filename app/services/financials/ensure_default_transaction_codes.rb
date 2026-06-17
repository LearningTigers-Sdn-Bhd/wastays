# frozen_string_literal: true

module Financials
  class EnsureDefaultTransactionCodes
    DEFAULTS = [
      { system_key: "room_revenue", code: "ROOM", name: "Room Revenue", kind: "charge", category: "accommodation", gl_account_code: "4010" },
      { system_key: "no_show_revenue", code: "NO_SHOW", name: "No-Show Revenue", kind: "charge", category: "no_show_charge", gl_account_code: "4030" },
      { system_key: "cancel_revenue", code: "CANCEL", name: "Cancellation Revenue", kind: "charge", category: "cancellation_charge", gl_account_code: "4033" },
      { system_key: "sst_tax", code: "TAX_SST", name: "SST", kind: "tax", category: "tax", gl_account_code: "2010" },
      { system_key: "tourism_tax", code: "TAX_TTX", name: "Tourism Tax", kind: "tax", category: "tax", gl_account_code: "2010" },
      { system_key: "fnb_revenue", code: "FNB", name: "Food & Beverage", kind: "charge", category: "fb", gl_account_code: "4020" },
      { system_key: "parking_revenue", code: "PARK", name: "Parking", kind: "charge", category: "parking", gl_account_code: "4090" },
      { system_key: "misc_revenue", code: "MISC", name: "Miscellaneous Revenue", kind: "charge", category: "other", gl_account_code: "4090" },
      { system_key: "cash_payment", code: "CASH", name: "Cash Payment", kind: "payment", category: "cash", gl_account_code: "1020" },
      { system_key: "card_payment", code: "CARD", name: "Card Payment", kind: "payment", category: "gateway_payment", gl_account_code: "1010" },
      { system_key: "bank_payment", code: "BANK", name: "Bank Transfer Payment", kind: "payment", category: "booking_payment", gl_account_code: "2020" },
      { system_key: "refund", code: "REFUND", name: "Refund", kind: "payment", category: "refund", gl_account_code: "1030" },
      { system_key: "adjustment", code: "ADJUSTMENT", name: "Adjustment", kind: "adjustment", category: "adjustment", gl_account_code: "5010" },
      { system_key: "rebate", code: "REBATE", name: "Rebate", kind: "adjustment", category: "discount", gl_account_code: "5030" }
    ].freeze

    CATEGORY_SYSTEM_KEYS = {
      "accommodation" => "room_revenue",
      "no_show_charge" => "no_show_revenue",
      "fb" => "fnb_revenue",
      "cash" => "cash_payment",
      "gateway_payment" => "card_payment",
      "booking_payment" => "bank_payment",
      "refund" => "refund",
      "adjustment" => "adjustment",
      "correction" => "adjustment",
      "discount" => "rebate",
      "write_off" => "adjustment",
      "other" => "misc_revenue"
    }.freeze

    def self.call(hotel)
      new(hotel).call
    end

    def self.system_key_for_category(category)
      CATEGORY_SYSTEM_KEYS[category.to_s]
    end

    def initialize(hotel)
      @hotel = hotel
    end

    def call
      DEFAULTS.each { |attributes| ensure_code!(attributes) }
      sync_primary_tax_codes!
    end

    private

    def ensure_code!(attributes)
      @hotel.transaction_codes.find_by(system_key: attributes[:system_key]) ||
        @hotel.transaction_codes.create!(attributes.merge(system_required: true, active: true))
    rescue ActiveRecord::RecordNotUnique
      @hotel.transaction_codes.find_by!(system_key: attributes[:system_key])
    end

    def sync_primary_tax_codes!
      @hotel.transaction_codes.find_by(system_key: "sst_tax")&.update!(active: @hotel.sst_enabled?)
      @hotel.transaction_codes.find_by(system_key: "tourism_tax")&.update!(active: @hotel.tourism_tax_enabled?)
    end
  end
end
