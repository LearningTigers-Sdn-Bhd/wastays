require "rails_helper"

RSpec.describe ExtraCharges::CreateForecasts do
  let(:business_date) { Date.new(2026, 8, 3) }
  let(:hotel) { create(:hotel, accounting_business_date: business_date, sst_enabled: true) }
  let(:booking) do
    create(:booking, hotel: hotel, status: "checked_in", check_in: business_date, check_out: business_date + 2.days)
  end
  let(:folio) { create(:booking_folio, hotel: hotel, booking: booking, is_primary: true) }
  let(:code) { create(:transaction_code, hotel: hotel, kind: "charge", category: "fb", code: "DINNER", is_taxable: true) }
  let(:extra_charge) do
    create(:hotel_extra_charge, hotel: hotel, transaction_code: code, pricing_type: "fixed", rate_value: 100,
      charging_unit: "per_night", allow_amount_override: false)
  end

  before do
    create(:booking_room, booking: booking)
    code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")
  end

  it "stores each dated base/tax pair in the existing folio forecast table" do
    quote = ExtraCharges::ForecastQuote.call(extra_charge: extra_charge, folio: folio, booking: booking)

    result = described_class.call(
      extra_charge: extra_charge,
      folio: folio,
      booking: booking,
      starts_on: quote.starts_on,
      ends_on: quote.ends_on,
      unit_rate: quote.unit_rate,
      expected_fingerprint: quote.fingerprint,
      description: "Dinner buffet",
      reference: "APPROVED",
      note: "Two nights"
    )

    expect(result).to be_success
    expect(result.forecasts.size).to eq(4)
    expect(result.forecasts.map(&:charge_kind)).to eq(%w[extra_charge extra_charge_tax extra_charge extra_charge_tax])
    expect(result.forecasts.map(&:stay_date).uniq).to eq([ business_date, business_date + 1.day ])
    expect(result.forecasts.map { |forecast| forecast.metadata["extra_charge_posting_key"] }.uniq).to contain_exactly(result.posting_group_key)
    base_descriptions = result.forecasts.select { |forecast| forecast.charge_kind == "extra_charge" }.map(&:description)
    expect(base_descriptions).to eq([
      "#{extra_charge.name} · MYR 100.00 · 2026-08-03",
      "#{extra_charge.name} · MYR 100.00 · 2026-08-04"
    ])
    expect(result.forecasts.select { |forecast| forecast.charge_kind == "extra_charge_tax" }.map(&:description)).to eq([
      "Tax: SST 8% for #{base_descriptions.first}",
      "Tax: SST 8% for #{base_descriptions.second}"
    ])
    expect(folio.folio_transactions).to be_empty

    Folios::Forecasts::SyncForecastedCharges.call(booking_folio: folio)
    expect(result.forecasts.map { |forecast| forecast.reload.status }).to all(eq("forecast"))
  end

  it "lets the existing nightly posting service actualize the due forecasts idempotently" do
    quote = ExtraCharges::ForecastQuote.call(extra_charge: extra_charge, folio: folio, booking: booking)
    created = described_class.call(
      extra_charge: extra_charge, folio: folio, booking: booking,
      starts_on: quote.starts_on, ends_on: quote.ends_on, unit_rate: quote.unit_rate,
      expected_fingerprint: quote.fingerprint
    )
    hotel.update!(sst_enabled: false)
    night_audit = create(:night_audit, hotel: hotel, business_date: business_date, status: "running", completed_at: nil)
    hotel.current_business_date_record.update!(status: "audit_running")

    first = Folios::Charges::PostNightlyCharges.call(night_audit: night_audit, user: nil)
    count_after_first = FolioTransaction.where("metadata ->> 'extra_charge_posting_key' = ?", created.posting_group_key).count
    second = Folios::Charges::PostNightlyCharges.call(night_audit: night_audit, user: nil)

    expect(first.failed).to be_empty
    expect(second.failed).to be_empty
    expect(count_after_first).to eq(2)
    expect(FolioTransaction.where("metadata ->> 'extra_charge_posting_key' = ?", created.posting_group_key).count).to eq(2)
    expect(FolioTransaction.where("metadata ->> 'extra_charge_posting_key' = ?", created.posting_group_key).pluck(:amount)).to contain_exactly(100.to_d, 8.to_d)
    expect(created.forecasts.select { |forecast| forecast.stay_date == business_date }.map { |forecast| forecast.reload.status }).to all(eq("actualized"))
    expect(created.forecasts.select { |forecast| forecast.stay_date > business_date }.map { |forecast| forecast.reload.status }).to all(eq("forecast"))
    expect(Folios::Charges::NightlyChargeReconciliation.call(booking: booking, business_date: business_date)).to be_valid
  end
end
