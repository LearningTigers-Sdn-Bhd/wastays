# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Reads::ForecastedChargeLines do
  it "returns accommodation and tax lines for each stay night" do
    booking = create(
      :booking,
      check_in: Date.current,
      check_out: Date.current + 2.days,
      tax_posting_snapshot: {
        Date.current.iso8601 => [ { "name" => "SST", "amount" => "6.00", "type" => "sst" } ],
        (Date.current + 1.day).iso8601 => [ { "name" => "SST", "amount" => "6.00", "type" => "sst" } ]
      }
    )
    booking_room = create(:booking_room, booking: booking, subtotal: 200)

    lines = described_class.call(booking: booking)

    expect(lines).to include(
      hash_including(stay_date: Date.current, charge_kind: "accommodation", identity: booking_room.id.to_s, amount: 100.to_d),
      hash_including(stay_date: Date.current, charge_kind: "tax", amount: 6.to_d)
    )
    expect(lines.size).to eq(4)
  end

  it "prefers immutable OTA component posting prices and preserves component identities" do
    booking = create(:booking, check_in: Date.current, check_out: Date.current + 1.day)
    room = create(:booking_room, booking: booking, subtotal: 999)
    snapshot = create(:ota_financial_snapshot, hotel: booking.hotel, booking: booking,
      original_currency: booking.currency, currency: booking.currency)
    room_code = booking.hotel.transaction_codes.find_by!(system_key: "room_revenue")
    fee_code = booking.hotel.transaction_codes.find_by!(system_key: "ota_unmapped_fee")
    tax_code = booking.hotel.transaction_codes.find_by!(system_key: "ota_unmapped_tax")
    rebate_code = booking.hotel.transaction_codes.find_by!(system_key: "rebate")

    create(:ota_financial_component, ota_financial_snapshot: snapshot, booking: booking,
      booking_room: room, transaction_code: room_code, stable_key: "room/0/date/0", amount: 120,
      posting_amount: 112, gross_effect_amount: 120)
    create(:ota_financial_component, ota_financial_snapshot: snapshot, booking: booking,
      booking_room: nil, transaction_code: fee_code, component_kind: "fee", stable_key: "fee/cleaning",
      provider_name: "Cleaning fee", amount: 15, posting_amount: 15, gross_effect_amount: 15)
    create(:ota_financial_component, ota_financial_snapshot: snapshot, booking: booking,
      booking_room: nil, transaction_code: tax_code, component_kind: "tax", stable_key: "tax/vat/inclusive",
      provider_name: "VAT", amount: 8, posting_amount: 8, gross_effect_amount: 0, is_inclusive: true)
    create(:ota_financial_component, ota_financial_snapshot: snapshot, booking: booking,
      booking_room: nil, transaction_code: rebate_code, component_kind: "discount", stable_key: "discount/member",
      provider_name: "Member deal", amount: 10, posting_amount: -10, gross_effect_amount: -10)

    lines = described_class.call(booking: booking)

    expect(lines.map { |line| [ line[:identity], line[:amount] ] }).to contain_exactly(
      [ "room/0/date/0", 112.to_d ], [ "fee/cleaning", 15.to_d ],
      [ "tax/vat/inclusive", 8.to_d ], [ "discount/member", -10.to_d ]
    )
    expect(lines.filter { |line| line[:charge_kind].in?(%w[accommodation tax]) }.sum { |line| line[:amount] }).to eq(120.to_d)
    expect(lines.find { |line| line[:identity] == "fee/cleaning" }[:charge_kind]).to eq("ota_fee")
    expect(lines.find { |line| line[:identity] == "discount/member" }).to include(
      charge_kind: "ota_discount", transaction_type: "adjustment", category: "discount"
    )
    expect(lines.first[:metadata]).to include(:ota_financial_snapshot_id, :ota_financial_component_id, :posting_amount)
  end

  it "does not suppress unmatched OTA components because another nightly charge exists on the date" do
    booking = create(:booking, check_in: Date.current, check_out: Date.tomorrow)
    create(:booking_room, booking: booking)
    Financials::EnsureDefaultTransactionCodes.call(booking.hotel)
    snapshot = create(:ota_financial_snapshot, hotel: booking.hotel, booking: booking,
      gross_amount: 25, accommodation_amount: 25)
    room_code = booking.hotel.transaction_codes.find_by!(system_key: "room_revenue")
    create(:ota_financial_component, ota_financial_snapshot: snapshot, booking: booking,
      booking_room: booking.booking_rooms.first, transaction_code: room_code,
      component_kind: "accommodation", stable_key: "ota-room-date", stay_date: Date.current,
      amount: 25, gross_effect_amount: 25, posting_amount: 25)
    folio = create(:booking_folio, booking: booking, hotel: booking.hotel)
    create(:folio_transaction, booking_folio: folio, transaction_code: room_code,
      posting_date: Date.current, amount: 5, transaction_type: "charge", category: "accommodation",
      metadata: { "nightly_charge_key" => "unrelated-nightly-charge", "stay_date" => Date.current.iso8601 })

    lines = described_class.call(booking: booking, dates: [ Date.current ])

    expect(lines.map { |line| line[:identity] }).to include("ota-room-date")
  end

  it "blocks financial projection when the OTA gross does not reconcile" do
    booking = create(:booking, check_in: Date.current, check_out: Date.current + 1.day)
    create(:booking_room, booking: booking, subtotal: 100)
    create(:ota_financial_snapshot, hotel: booking.hotel, booking: booking,
      reconciliation_status: "total_mismatch", mismatch_amount: 1)

    expect(described_class.call(booking: booking)).to eq([])
  end
end
