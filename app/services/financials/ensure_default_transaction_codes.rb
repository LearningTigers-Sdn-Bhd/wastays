# frozen_string_literal: true

module Financials
  class EnsureDefaultTransactionCodes
    DEFAULTS = [
      { system_key: "room_revenue", code: "ROOM", name: "Room Revenue", kind: "charge", category: "accommodation", gl_account_code: "4010" },
      { system_key: "no_show_revenue", code: "NO_SHOW", name: "No-Show Revenue", kind: "charge", category: "no_show_charge", gl_account_code: "4030" },
      { system_key: "cancel_revenue", code: "CANCEL", name: "Cancellation Revenue", kind: "charge", category: "cancellation_charge", gl_account_code: "4033" },
      { system_key: "late_checkout_revenue", code: "LATE_CO", name: "Late Checkout Revenue", kind: "charge", category: "late_checkout_charge", gl_account_code: "4031" },
      { system_key: "early_departure_revenue", code: "EARLY_DEP", name: "Early Departure Revenue", kind: "charge", category: "early_departure_charge", gl_account_code: "4032" },
      { system_key: "security_deposit", code: "SECDEP", name: "Security Deposit", kind: "payment", category: "security_deposit", gl_account_code: "2030" },
      { system_key: "sst_tax", code: "TAX_SST", name: "SST", kind: "tax", category: "tax", gl_account_code: "2010" },
      { system_key: "tourism_tax", code: "TAX_TTX", name: "Tourism Tax", kind: "tax", category: "tax", gl_account_code: "2010" },
      { system_key: "fnb_revenue", code: "FNB", name: "Food & Beverage", kind: "charge", category: "fb", gl_account_code: "4020" },
      { system_key: "parking_revenue", code: "PARK", name: "Parking", kind: "charge", category: "parking", gl_account_code: "4090" },
      { system_key: "damage_revenue", code: "DAMAGE", name: "Damage Charge", kind: "charge", category: "other", gl_account_code: "4090" },
      { system_key: "cleaning_revenue", code: "CLEANING", name: "Cleaning Fee", kind: "charge", category: "other", gl_account_code: "4090" },
      { system_key: "misc_revenue", code: "MISC", name: "Miscellaneous Revenue", kind: "charge", category: "other", gl_account_code: "4090" },
      { system_key: "cash_payment", code: "CASH", name: "Cash Payment", kind: "payment", category: "cash", gl_account_code: "1020" },
      { system_key: "card_payment", code: "CARD", name: "Card Payment", kind: "payment", category: "gateway_payment", gl_account_code: "1010" },
      { system_key: "bank_payment", code: "BANK", name: "Bank Transfer Payment", kind: "payment", category: "booking_payment", gl_account_code: "2020" },
      { system_key: "gateway_manual_recovery_payment", code: "GATEWAY", name: "Gateway Manual Recovery", kind: "payment", category: "gateway_payment", gl_account_code: "1010" },
      { system_key: "ota_collected_payment", code: "OTA", name: "OTA Collected", kind: "payment", category: "booking_payment", gl_account_code: "2020" },
      { system_key: "refund", code: "REFUND", name: "Refund", kind: "payment", category: "refund", gl_account_code: "1030" },
      { system_key: "adjustment", code: "ADJUSTMENT", name: "Adjustment", kind: "adjustment", category: "adjustment", gl_account_code: "5010" },
      { system_key: "rebate", code: "REBATE", name: "Rebate", kind: "adjustment", category: "discount", gl_account_code: "5030" }
    ].freeze

    CATEGORY_SYSTEM_KEYS = {
      "accommodation" => "room_revenue",
      "no_show_charge" => "no_show_revenue",
      "late_checkout_charge" => "late_checkout_revenue",
      "early_departure_charge" => "early_departure_revenue",
      "fb" => "fnb_revenue",
      "cash" => "cash_payment",
      "gateway_payment" => "card_payment",
      "booking_payment" => "bank_payment",
      "security_deposit" => "security_deposit",
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
      # Query the model class directly (not the `@hotel.transaction_codes` association proxy):
      # the association may already be cached/loaded (e.g. after a prior `destroy_all`), in
      # which case `pluck` would silently serve stale in-memory data instead of hitting the DB.
      existing_system_keys, existing_codes = TransactionCode.where(hotel_id: @hotel.id).pluck(:system_key, :code).transpose.then do |keys, codes|
        [ (keys || []).to_set, (codes || []).to_set ]
      end

      now = Time.current
      rows = DEFAULTS.filter_map do |attributes|
        next if existing_system_keys.include?(attributes[:system_key])

        code = available_code(attributes[:code], existing_codes)
        existing_codes << code

        attributes.merge(hotel_id: @hotel.id, code: code, system_required: true, active: true, created_at: now, updated_at: now)
      end

      TransactionCode.insert_all(rows, unique_by: :index_transaction_codes_on_hotel_id_and_system_key) if rows.any?
      @hotel.transaction_codes.reset

      sync_primary_tax_codes!
    end

    private

    def available_code(code, existing_codes)
      return code unless existing_codes.include?(code)

      suffix = 2
      candidate = "#{code}_#{suffix}"
      while existing_codes.include?(candidate)
        suffix += 1
        candidate = "#{code}_#{suffix}"
      end
      candidate
    end

    def sync_primary_tax_codes!
      @hotel.transaction_codes.find_by(system_key: "sst_tax")&.update!(active: @hotel.sst_enabled?)
      @hotel.transaction_codes.find_by(system_key: "tourism_tax")&.update!(active: @hotel.tourism_tax_enabled?)
    end
  end
end
