# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::Bookings::GenerateSummaryExtraCharges do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel:) }
  let(:folio) { create(:booking_folio, booking:, hotel:) }
  let(:date) { booking.check_in.to_date }

  def report(bookings: [ booking ], group: false)
    described_class.new(hotel:, bookings:, group:).call
  end

  def forecast(folio: self.folio, kind: "extra_charge", amount: 20, **attributes)
    create(:folio_forecasted_charge, booking_folio: folio, stay_date: date,
      charge_kind: kind, identity: "jetty:base", amount:,
      description: "Tourist Jetty Fee - 2 x MYR 10.00",
      metadata: { extra_charge_id: 123, quantity: 2, transaction_code_code: "JETTY" }, **attributes)
  end

  def charge(folio: self.folio, amount: 20, **attributes)
    create(:folio_transaction, booking_folio: folio, amount:, category: "other",
      description: "Tourist Jetty Fee - 2 x MYR 10.00",
      metadata: { extra_charge_id: 123, extra_charge_quantity: "2" }, **attributes)
  end

  it "uses saved forecast amounts, quantities and codes" do
    forecast
    expect(report.charge_rows.first).to have_attributes(code: "JETTY", quantity: "2", net: 20.to_d, charges: nil, gross: 20.to_d)
    expect(report.total).to eq(20.to_d)
  end

  it "keeps the same total after posting without counting the actualized forecast" do
    scheduled = forecast
    posted = charge(metadata: { extra_charge_id: 123, forecast_id: scheduled.id, stay_date: date.iso8601 })
    scheduled.actualize!(transaction: posted)
    expect(report.total).to eq(20.to_d)
    expect(report.charge_rows.size).to eq(1)
    expect(report.charge_rows.first.date).to eq(Reports::Bookings::GenerateReservationRecords::PdfTheme.format_date(date))
  end

  it "suppresses a still-active forecast linked to a posted transaction" do
    scheduled = forecast
    charge(metadata: { extra_charge_id: 123, forecast_id: scheduled.id })
    expect(report.total).to eq(20.to_d)
    expect(report.charge_rows.size).to eq(1)
  end

  it "also matches the saved forecast identity, kind and date" do
    scheduled = forecast
    charge(metadata: { extra_charge_id: 123, forecast_identity: scheduled.identity,
      charge_kind: scheduled.charge_kind, stay_date: date.iso8601 })
    expect(report.total).to eq(20.to_d)
  end

  it "includes staff-posted extras and attached taxes routed to another folio" do
    parent = charge
    other_folio = create(:booking_folio, :secondary, booking:, hotel:)
    create(:folio_transaction, booking_folio: other_folio, amount: 1.60, category: "tax",
      description: "SST on jetty fee", metadata: { parent_folio_transaction_id: parent.id, tax_line: { type: "sst" } })
    expect(report.base_total).to eq(20.to_d)
    expect(report.tax_total).to eq(1.60.to_d)
    expect(report.charge_rows.last).to have_attributes(net: nil, charges: 1.60.to_d, gross: 1.60.to_d, quantity: "-")
  end

  it "includes scheduled attached taxes but excludes TTX and superseded forecasts" do
    forecast
    forecast(kind: "extra_charge_tax", amount: 1.60, identity: "jetty:sst")
    forecast(kind: "extra_charge_tax", amount: 10, identity: "jetty:ttx", metadata: { tax_rule_key: "primary:tourism_tax" })
    forecast(amount: 40, identity: "old", status: "superseded")
    expect(report.total).to eq(21.60.to_d)
  end

  it "excludes reversed charges and their reversal entries" do
    original = charge
    reversal = create(:folio_transaction, booking_folio: folio, transaction_type: "adjustment", category: "correction",
      amount: -20, reversal_of_transaction: original, metadata: original.metadata)
    original.update_columns(voided_by_transaction_id: reversal.id)
    expect(report.charge_rows).to be_empty
  end

  it "counts active replacements after moves and splits without reviving the original" do
    original = charge
    scheduled = forecast
    scheduled.actualize!(transaction: original)
    reversal = create(:folio_transaction, booking_folio: folio, transaction_type: "adjustment", category: "correction",
      amount: -20, reversal_of_transaction: original)
    original.update_columns(voided_by_transaction_id: reversal.id)
    other_folio = create(:booking_folio, :secondary, booking:, hotel:)
    moved = charge(folio: other_folio, moved_from_transaction: original, metadata: { extra_charge_id: 123, forecast_id: scheduled.id })
    moved_reversal = create(:folio_transaction, booking_folio: other_folio, transaction_type: "adjustment", category: "correction",
      amount: -20, reversal_of_transaction: moved)
    moved.update_columns(voided_by_transaction_id: moved_reversal.id)
    charge(amount: 12, split_from_transaction: moved, metadata: moved.metadata)
    charge(folio: other_folio, amount: 8, split_from_transaction: moved, metadata: moved.metadata)
    expect(report.total).to eq(20.to_d)
    expect(report.charge_rows.size).to eq(2)
  end

  it "excludes unrelated folio charges, adjustments and posted tourism tax" do
    charge
    create(:folio_transaction, booking_folio: folio, amount: 100, category: "accommodation")
    create(:folio_transaction, booking_folio: folio, amount: 5, transaction_type: "adjustment", category: "correction")
    charge(amount: 10, category: "tax", metadata: { extra_charge_id: 123, tax_line: { type: "tourism_tax" } })
    expect(report.total).to eq(20.to_d)
  end

  it "scopes charges to the requested hotel and bookings" do
    forecast
    other = create(:booking, hotel:)
    charge(folio: create(:booking_folio, booking: other, hotel:), amount: 50)
    foreign_hotel = create(:hotel)
    foreign_booking = create(:booking, hotel: foreign_hotel)
    charge(folio: create(:booking_folio, booking: foreign_booking, hotel: foreign_hotel), amount: 80)
    expect(report.total).to eq(20.to_d)
  end

  it "qualifies each child's extras with its booking reference on group reports" do
    forecast
    other = create(:booking, hotel:)
    charge(folio: create(:booking_folio, booking: other, hotel:), amount: 30)
    result = report(bookings: [ booking, other ], group: true)
    expect(result.total).to eq(50.to_d)
    expect(result.charge_rows.map(&:secondary_description)).to contain_exactly(booking.confirmation_token, other.confirmation_token)
  end
end
