# frozen_string_literal: true

require "rails_helper"

RSpec.describe Financials::EnsureDefaultTransactionCodes, type: :service do
  let(:hotel) { create(:hotel) }

  describe ".call" do
    it "creates the default transaction codes for a hotel" do
      hotel.transaction_codes.destroy_all

      expect {
        described_class.call(hotel)
      }.to change { hotel.transaction_codes.count }.from(0).to(14)

      expect(hotel.transaction_codes.system_required.pluck(:code)).to contain_exactly(
        "ROOM", "NO_SHOW", "CANCEL", "TAX_SST", "TAX_TTX", "FNB", "PARK", "MISC", "CASH", "CARD", "BANK", "REFUND", "ADJUSTMENT", "REBATE"
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
  end
end
