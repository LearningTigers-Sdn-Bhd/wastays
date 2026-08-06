# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExtraCharges::ForecastQuote, type: :service do
  let(:business_date) { Date.new(2026, 8, 3) }
  let(:hotel) { create(:hotel, accounting_business_date: business_date, sst_enabled: true) }
  let(:booking) do
    create(:booking, hotel: hotel, status: "checked_in", check_in: business_date, check_out: business_date + 2.days,
      adults: 2, children: 1)
  end
  let(:folio) { create(:booking_folio, hotel: hotel, booking: booking, is_primary: true) }
  let(:transaction_code) do
    create(:transaction_code, hotel: hotel, kind: "charge", category: "fb", code: "DINNER", is_taxable: true)
  end
  let(:extra_charge) do
    create(:hotel_extra_charge, hotel: hotel, transaction_code: transaction_code, pricing_type: "fixed",
      rate_value: 50, charging_unit: "per_person_night", allow_amount_override: false)
  end

  before do
    create(:booking_room, booking: booking)
    transaction_code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")
  end

  describe ".call" do
    it "builds dated base and tax rows for the remaining occupied nights" do
      result = described_class.call(extra_charge: extra_charge, folio: folio, booking: booking)

      expect(result).to be_success
      expect(result.allowed_dates).to eq([ business_date, business_date + 1.day ])
      expect(result.starts_on).to eq(business_date)
      expect(result.ends_on).to eq(business_date + 1.day)
      expect(result.unit_rate).to eq(50.to_d)
      expect(result.base_total).to eq(300.to_d)
      expect(result.tax_total).to eq(24.to_d)
      expect(result.grand_total).to eq(324.to_d)
      expect(result.fingerprint).to be_present

      first_row = result.dates.first
      expect(first_row).to include(
        date: business_date,
        quantity: 3,
        unit_rate: 50.to_d,
        base_amount: 150.to_d,
        tax_total: 12.to_d,
        total: 162.to_d,
        posting_state: "upcoming"
      )
      expect(first_row[:taxes].first).to include(
        name: "SST 8%",
        amount: 12.to_d,
        rate_type: "percentage",
        rate: 8.to_d,
        transaction_code_code: "TAX_SST",
        target_folio_id: folio.id
      )
    end

    it "uses the configured rate until the extra charge allows an override" do
      configured = described_class.call(extra_charge: extra_charge, folio: folio, booking: booking, unit_rate: 75)

      expect(configured).to be_success
      expect(configured.unit_rate).to eq(50.to_d)
      expect(configured.base_total).to eq(300.to_d)
      expect(configured.grand_total).to eq(324.to_d)

      extra_charge.update!(allow_amount_override: true)
      accepted = described_class.call(extra_charge: extra_charge, folio: folio, booking: booking, unit_rate: 75)

      expect(accepted).to be_success
      expect(accepted.unit_rate).to eq(75.to_d)
      expect(accepted.base_total).to eq(450.to_d)
      expect(accepted.grand_total).to eq(486.to_d)
    end

    it "rejects dates outside the remaining occupied nights" do
      result = described_class.call(
        extra_charge: extra_charge,
        folio: folio,
        booking: booking,
        starts_on: business_date + 2.days,
        ends_on: business_date + 2.days
      )

      expect(result).not_to be_success
      expect(result.error).to eq("Select dates within the remaining stay.")
      expect(result.allowed_dates).to eq([ business_date, business_date + 1.day ])
    end

    it "returns refreshed details when the expected fingerprint is stale" do
      initial = described_class.call(extra_charge: extra_charge, folio: folio, booking: booking)
      extra_charge.update!(rate_value: 60)

      result = described_class.call(
        extra_charge: extra_charge,
        folio: folio,
        booking: booking,
        expected_fingerprint: initial.fingerprint
      )

      expect(result).not_to be_success
      expect(result.error).to include("Charge details changed")
      expect(result.configured_rate).to eq(60.to_d)
      expect(result.grand_total).to eq(388.8.to_d)
    end

    it "rejects charges that are not fixed nightly charges available to the booking" do
      extra_charge.update!(charging_unit: "per_item")

      result = described_class.call(extra_charge: extra_charge, folio: folio, booking: booking)

      expect(result).not_to be_success
      expect(result.error).to eq("Only fixed night-based extra charges can be scheduled.")

      extra_charge.update!(charging_unit: "per_night")
      transaction_code.update!(active: false)

      result = described_class.call(extra_charge: extra_charge, folio: folio, booking: booking)

      expect(result).not_to be_success
      expect(result.error).to eq("Extra charge is not available for this booking.")
    end
  end
end
