# frozen_string_literal: true

require "rails_helper"

RSpec.describe Financials::EnsureDefaultTransactionCodes, type: :service do
  let(:hotel) { create(:hotel) }

  describe ".call" do
    it "creates the default transaction codes for a hotel" do
      hotel.transaction_codes.destroy_all

      expect {
        described_class.call(hotel)
      }.to change { hotel.transaction_codes.count }.from(0).to(25)

      expect(hotel.transaction_codes.system_required.pluck(:code)).to contain_exactly(
        "ROOM", "NO_SHOW", "CANCEL", "LATE_CO", "EARLY_DEP", "SECDEP", "TAX_SST", "TAX_TTX", "FNB", "PARK", "DAMAGE", "CLEANING", "OTA_FEE", "OTA_TAX", "MISC", "CASH", "CASH_ADV", "CARD", "CARD_ADV", "BANK", "GATEWAY", "OTA", "REFUND", "ADJUSTMENT", "REBATE"
      )
      expect(hotel.transaction_codes.find_by!(system_key: "cash_prepayment")).to have_attributes(code: "CASH_ADV", category: "booking_payment", gl_account_code: "2020")
      expect(hotel.transaction_codes.find_by!(system_key: "card_prepayment")).to have_attributes(code: "CARD_ADV", category: "booking_payment", gl_account_code: "2020")
      expect(hotel.transaction_codes.find_by!(system_key: "gateway_manual_recovery_payment")).to have_attributes(code: "GATEWAY", category: "gateway_payment", gl_account_code: "1010")
      expect(hotel.transaction_codes.find_by!(system_key: "ota_collected_payment")).to have_attributes(code: "OTA", category: "booking_payment", gl_account_code: "2020")
      expect(hotel.transaction_codes.find_by!(system_key: "security_deposit")).to have_attributes(code: "SECDEP", category: "security_deposit", gl_account_code: "2030")
      expect(hotel.transaction_codes.find_by!(system_key: "damage_revenue")).to have_attributes(code: "DAMAGE", category: "other", gl_account_code: "4090", is_taxable: false)
      expect(hotel.transaction_codes.find_by!(system_key: "cleaning_revenue")).to have_attributes(code: "CLEANING", category: "other", gl_account_code: "4090", is_taxable: false)
      expect(hotel.transaction_codes.find_by!(system_key: "ota_unmapped_fee")).to have_attributes(
        code: "OTA_FEE", name: "OTA Unmapped Fee", kind: "charge", category: "other",
        gl_account_code: "4090", system_required: true, active: true
      )
      expect(hotel.transaction_codes.find_by!(system_key: "ota_unmapped_tax")).to have_attributes(
        code: "OTA_TAX", name: "OTA Unmapped Tax", kind: "tax", category: "tax",
        gl_account_code: "2010", system_required: true, active: true
      )
    end

    it "is idempotent" do
      expect {
        described_class.call(hotel)
      }.not_to change { hotel.transaction_codes.count }
    end

    it "does not overwrite hotel-facing code customizations" do
      room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
      room_code.update!(code: "ROOM-01")

      described_class.call(hotel)

      expect(room_code.reload.code).to eq("ROOM-01")
    end

    it "uses an available hotel-facing code when a new default code is already taken" do
      hotel.transaction_codes.destroy_all
      create(:transaction_code, hotel: hotel, code: "SECDEP", system_key: "custom_secdep")

      described_class.call(hotel)

      security_deposit_code = hotel.transaction_codes.find_by!(system_key: "security_deposit")
      expect(security_deposit_code.code).to eq("SECDEP_2")
      expect(security_deposit_code.category).to eq("security_deposit")
    end
  end
end
