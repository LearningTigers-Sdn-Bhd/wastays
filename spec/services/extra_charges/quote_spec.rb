require "rails_helper"

RSpec.describe ExtraCharges::Quote do
  let(:booking) { create(:booking, check_in: Date.current, check_out: 3.days.from_now, adults: 2, children: 1) }
  let(:folio) { create(:booking_folio, booking: booking, hotel: booking.hotel) }

  before { create(:booking_room, booking: booking) }

  it "uses the staff-entered amount for manual pricing" do
    extra_charge = create(:hotel_extra_charge, hotel: booking.hotel, pricing_type: "manual")

    result = described_class.call(extra_charge:, folio:, booking:, requested_amount: 42)

    expect(result).to be_success
    expect(result.amount).to eq(42.to_d)
    expect(result.metadata).to include(extra_charge_id: extra_charge.id, extra_charge_pricing_type: "manual")
  end

  {
    "per_item" => 4,
    "per_stay" => 1,
    "per_night" => 3,
    "per_room" => 1,
    "per_room_night" => 3,
    "per_person" => 3,
    "per_person_night" => 9
  }.each do |unit, expected_quantity|
    it "calculates fixed pricing #{unit.humanize.downcase}" do
      extra_charge = create(:hotel_extra_charge, hotel: booking.hotel, pricing_type: "fixed", rate_value: 10,
        charging_unit: unit, allow_amount_override: false)

      result = described_class.call(extra_charge:, folio:, booking:, quantity: 4, requested_amount: 999)

      expect(result).to be_success
      expect(result.quantity).to eq(expected_quantity.to_d)
      expect(result.amount).to eq((expected_quantity * 10).to_d)
    end
  end

  it "allows an enabled fixed-price override and records it" do
    extra_charge = create(:hotel_extra_charge, hotel: booking.hotel, pricing_type: "fixed", rate_value: 10,
      allow_amount_override: true)

    result = described_class.call(extra_charge:, folio:, booking:, quantity: 2, requested_amount: 25)

    expect(result.amount).to eq(25.to_d)
    expect(result.metadata[:extra_charge_amount_override]).to eq("25.0")
  end

  it "calculates a percentage from room charges and detects stale previews" do
    create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "accommodation", amount: 100)
    create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "other", amount: 50)
    extra_charge = create(:hotel_extra_charge, hotel: booking.hotel, pricing_type: "percentage", rate_value: 10,
      percentage_basis: "room_charges", allow_amount_override: false)
    preview = described_class.call(extra_charge:, folio:, booking:, preview: true)

    expect(preview.amount).to eq(10.to_d)

    create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "accommodation", amount: 25)
    result = described_class.call(extra_charge:, folio:, booking:, expected_fingerprint: preview.fingerprint)

    expect(result).not_to be_success
    expect(result.error).to include("Folio charges changed")
    expect(result.amount).to eq(12.5.to_d)
  end

  it "excludes taxes and prior percentage charges from the non-tax basis" do
    create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "other", amount: 100)
    create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "tax", amount: 8)
    create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "other", amount: 10,
      metadata: { extra_charge_pricing_type: "percentage" })
    extra_charge = create(:hotel_extra_charge, hotel: booking.hotel, pricing_type: "percentage", rate_value: 5,
      percentage_basis: "non_tax_charges", allow_amount_override: false)

    result = described_class.call(extra_charge:, folio:, booking:, preview: true)

    expect(result.base_amount).to eq(100.to_d)
    expect(result.amount).to eq(5.to_d)
  end
end
