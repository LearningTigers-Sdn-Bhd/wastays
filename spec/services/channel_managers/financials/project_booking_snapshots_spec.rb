# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelManagers::Financials::ProjectBookingSnapshots do
  it "projects accommodation and taxes while preserving snapshots for posted stay dates" do
    hotel = create(:hotel)
    booking = create(:booking, hotel:, check_in: Date.new(2026, 8, 11), check_out: Date.new(2026, 8, 13),
      tax_posting_snapshot: {
        "2026-08-11" => [ { "name" => "Posted tax", "type" => "ota_tax", "is_inclusive" => false,
          "amount" => "9.00", "currency" => "MYR", "source" => "ota_supplied" } ]
      })
    room = create(:booking_room, booking:, nightly_rate_snapshot: {
      "2026-08-11" => { "date" => "2026-08-11", "price" => "90.00", "source" => "posted" }
    })
    snapshot = create(:ota_financial_snapshot, hotel:, booking:, exchange_rate: 1.25,
      exchange_rate_source: "daily_rate")
    accommodation_code = create(:transaction_code, hotel:, kind: "charge", category: "accommodation")
    tax_code = create(:transaction_code, hotel:, kind: "charge", category: "tax")

    create(:ota_financial_component, ota_financial_snapshot: snapshot, booking:, booking_room: room,
      transaction_code: accommodation_code, stable_key: "room/posted", stay_date: Date.new(2026, 8, 11),
      amount: 100, posting_amount: 100)
    create(:ota_financial_component, ota_financial_snapshot: snapshot, booking:, booking_room: room,
      transaction_code: accommodation_code, stable_key: "room/open", stay_date: Date.new(2026, 8, 12),
      amount: 120, posting_amount: 120)
    create(:ota_financial_component, ota_financial_snapshot: snapshot, booking:, booking_room: room,
      transaction_code: tax_code, component_kind: "tax", stable_key: "tax/open", stay_date: Date.new(2026, 8, 12),
      provider_name: "Tourism tax", provider_type: nil, amount: 12, posting_amount: 12,
      original_amount: 10, original_currency: "USD", rate_type: "flat", rate: 12, basis: "night",
      basis_amount: 100)
    folio = create(:booking_folio, hotel:, booking:)
    create(:folio_transaction, booking_folio: folio, transaction_code: accommodation_code,
      posting_date: Date.new(2026, 8, 11), metadata: {
        "nightly_charge_key" => "night/posted", "stay_date" => "2026-08-11"
      })

    expect(described_class.call!(snapshot:)).to eq(snapshot)

    room.reload
    booking.reload
    expect(room.subtotal).to eq(210.to_d)
    expect(room.nightly_rate_snapshot.dig("2026-08-11", "price")).to eq("90.00")
    expect(room.nightly_rate_snapshot.dig("2026-08-12")).to include(
      "price" => "120.0", "posting_price" => "120.0", "exchange_rate" => "1.25",
      "exchange_rate_source" => "daily_rate", "ota_component_stable_key" => "room/open"
    )
    expect(booking.tax_posting_snapshot["2026-08-11"].first["name"]).to eq("Posted tax")
    expect(booking.tax_posting_snapshot["2026-08-12"].first).to include(
      "name" => "Tourism tax", "type" => "ota_tax", "amount" => "12.0",
      "original_amount" => "10.0", "transaction_code_id" => tax_code.id
    )
    expect(booking.tax_lines).to contain_exactly(
      include("name" => "Posted tax", "amount" => "9.0"),
      include("name" => "Tourism tax", "amount" => "12.0")
    )
  end

  it "adds hotel-managed tourism tax to a foreign guest's OTA projection" do
    hotel = create(:hotel, tourism_tax_enabled: true, tourism_tax_amount: 10)
    room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    room_code.update!(is_taxable: true)
    room_code.transaction_code_taxes.create!(primary_tax_key: "tourism_tax")
    booking = create(:booking, hotel:, guest_country: "Singapore",
      check_in: Date.new(2026, 9, 1), check_out: Date.new(2026, 9, 3))
    room = create(:booking_room, booking:, subtotal: 200)
    snapshot = create(:ota_financial_snapshot, hotel:, booking:, gross_amount: 200, accommodation_amount: 200)

    [ Date.new(2026, 9, 1), Date.new(2026, 9, 2) ].each_with_index do |date, index|
      create(:ota_financial_component, ota_financial_snapshot: snapshot, booking:, booking_room: room,
        transaction_code: room_code, stable_key: "room/#{index}", stay_date: date,
        amount: 100, posting_amount: 100, gross_effect_amount: 100)
    end

    described_class.call!(snapshot:)

    expect(booking.reload.tax_posting_snapshot.values.flatten).to contain_exactly(
      include("type" => "tourism_tax", "amount" => "10.0", "source" => "transaction_code_tax_rule"),
      include("type" => "tourism_tax", "amount" => "10.0", "source" => "transaction_code_tax_rule")
    )
    expect(Folios::Reads::ForecastedChargeLines.call(booking:).map { |line| [ line[:charge_kind], line[:amount] ] })
      .to contain_exactly(
        [ "accommodation", 100.to_d ], [ "accommodation", 100.to_d ],
        [ "tax", 10.to_d ], [ "tax", 10.to_d ]
      )
    expect(snapshot.ota_financial_components.sum(:gross_effect_amount)).to eq(200.to_d)
  end

  it "does not duplicate tourism tax already supplied by the OTA" do
    hotel = create(:hotel, tourism_tax_enabled: true, tourism_tax_amount: 10)
    room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    room_code.update!(is_taxable: true)
    room_code.transaction_code_taxes.create!(primary_tax_key: "tourism_tax")
    booking = create(:booking, hotel:, guest_country: "Singapore",
      check_in: Date.new(2026, 9, 1), check_out: Date.new(2026, 9, 2))
    room = create(:booking_room, booking:)
    snapshot = create(:ota_financial_snapshot, hotel:, booking:)
    create(:ota_financial_component, ota_financial_snapshot: snapshot, booking:, booking_room: room,
      transaction_code: room_code, stable_key: "room/0", stay_date: booking.check_in.to_date,
      amount: 100, posting_amount: 100, gross_effect_amount: 100)
    create(:ota_financial_component, ota_financial_snapshot: snapshot, booking:,
      transaction_code: hotel.transaction_codes.find_by!(system_key: "ota_unmapped_tax"),
      component_kind: "tax", stable_key: "tax/ttx", stay_date: booking.check_in.to_date,
      provider_name: "Tourism Tax", amount: 10, posting_amount: 10, gross_effect_amount: 10)

    described_class.call!(snapshot:)

    expect(booking.reload.tax_posting_snapshot.values.flatten).to contain_exactly(
      include("name" => "Tourism Tax", "amount" => "10.0", "source" => "ota_supplied")
    )
  end
end
