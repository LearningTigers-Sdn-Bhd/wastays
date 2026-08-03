# frozen_string_literal: true

require "rails_helper"

RSpec.describe Financials::EnsureDefaultExtraCharges, type: :service do
  let(:hotel) { create(:hotel) }

  describe ".call" do
    it "creates one manual extra charge for each default revenue code" do
      expect {
        described_class.call(hotel)
      }.to change { hotel.hotel_extra_charges.count }.from(0).to(5)

      charges = hotel.hotel_extra_charges.includes(:transaction_code).order(:position)

      expect(charges.map { |charge| charge.transaction_code.system_key }).to contain_exactly(
        "fnb_revenue", "parking_revenue", "damage_revenue", "cleaning_revenue", "misc_revenue"
      )
      expect(charges.map(&:position)).to eq([ 1, 2, 3, 4, 5 ])
      expect(charges).to all(have_attributes(
        pricing_type: "manual",
        charging_unit: "per_item",
        allow_amount_override: true
      ))
    end

    it "is idempotent" do
      described_class.call(hotel)

      expect {
        described_class.call(hotel)
      }.not_to change { hotel.hotel_extra_charges.count }
    end

    it "preserves existing extra charges and appends defaults after the highest position" do
      existing_code = hotel.transaction_codes.find_by!(system_key: "fnb_revenue")
      existing = create(
        :hotel_extra_charge,
        hotel: hotel,
        transaction_code: existing_code,
        pricing_type: "fixed",
        rate_value: 25,
        charging_unit: "per_night",
        allow_amount_override: false,
        position: 7
      )

      expect {
        described_class.call(hotel)
      }.to change { hotel.hotel_extra_charges.count }.from(1).to(5)

      expect(existing.reload).to have_attributes(
        pricing_type: "fixed",
        rate_value: 25.to_d,
        charging_unit: "per_night",
        allow_amount_override: false,
        position: 7
      )
      expect(hotel.hotel_extra_charges.where.not(id: existing.id).order(:position).pluck(:position)).to eq([ 8, 9, 10, 11 ])
    end
  end
end
