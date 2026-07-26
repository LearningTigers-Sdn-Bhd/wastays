# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Reads::RoutePreview do
  let(:business_date) { Date.current }
  let(:hotel) { create(:hotel) }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      check_in: business_date,
      check_out: business_date + 1.day)
  end
  let!(:room) { create(:booking_room, booking: booking, subtotal: 100.0) }
  let!(:guest_folio) { create(:booking_folio, hotel: hotel, booking: booking) }
  let!(:company_folio) { create(:booking_folio, :secondary, hotel: hotel, booking: booking) }

  before do
    hotel.update!(sst_enabled: true, tourism_tax_enabled: true, tourism_tax_amount: 10)
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    booking.update!(tax_posting_snapshot: {
      business_date.iso8601 => [
        { "name" => "SST", "amount" => "8.00", "type" => "sst", "transaction_code_id" => sst_code.id },
        { "name" => "Tourism Tax", "amount" => "10.00", "type" => "tourism_tax", "transaction_code_id" => ttx_code.id }
      ]
    })
  end

  let(:room_code) { hotel.transaction_codes.find_by!(system_key: "room_revenue") }
  let(:sst_code) { hotel.transaction_codes.find_by!(system_key: "sst_tax") }
  let(:ttx_code) { hotel.transaction_codes.find_by!(system_key: "tourism_tax") }

  it "returns flat rows and rows grouped by target folio" do
    create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: room_code, target_folio: company_folio)
    create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: sst_code, target_folio: company_folio)
    create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: ttx_code, target_folio: guest_folio)

    result = described_class.call(booking: booking)

    expect(result.rows.size).to eq(3)
    expect(result.grouped_by_folio[company_folio].size).to eq(2)
    expect(result.grouped_by_folio[guest_folio].size).to eq(1)
    expect(result.rows.map { |row| row[:display_code_label] }).to contain_exactly("ROOM", "ROOM_TAX_SST", "ROOM_TAX_TTX")
    expect(result.rows.map { |row| row[:warning] }).to all(be_nil)
  end

  it "shows warnings for missing transaction codes" do
    booking.update!(tax_posting_snapshot: {
      business_date.iso8601 => [ { "name" => "Local Tax", "amount" => "5.00", "type" => "local" } ]
    })

    result = described_class.call(booking: booking)
    tax_row = result.rows.find { |row| row[:description].include?("Local Tax") }

    expect(tax_row[:warning]).to eq("Missing transaction code")
    expect(tax_row[:target_folio]).to be_nil
  end

  it "routing changes affect preview and do not move posted transactions" do
    posted = create(:folio_transaction,
      booking_folio: guest_folio,
      transaction_type: "charge",
      category: "accommodation",
      amount: 100.0,
      transaction_code: room_code,
      metadata: { nightly_charge_key: Folios::ChargePostingKeys.nightly_charge_key(booking: booking, date: business_date, charge_kind: "accommodation", identity: room.id) })
    create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: room_code, target_folio: company_folio)

    room_row = described_class.call(booking: booking).rows.find { |row| row[:transaction_code] == room_code }

    expect(room_row[:target_folio]).to eq(company_folio)
    expect(posted.reload.booking_folio).to eq(guest_folio)
  end

  it "routes attached taxes with the parent ROOM rule unless explicitly overridden" do
    create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: room_code, target_folio: company_folio)
    booking.update!(tax_posting_snapshot: {
      business_date.iso8601 => [
        {
          "name" => "SST",
          "amount" => "8.00",
          "type" => "sst",
          "transaction_code_id" => sst_code.id,
          "source_transaction_code_id" => room_code.id
        }
      ]
    })

    tax_row = described_class.call(booking: booking).rows.find { |row| row[:transaction_code] == sst_code }

    expect(tax_row[:target_folio]).to eq(company_folio)
    expect(tax_row[:route_source]).to eq("follows_parent")
  end
end
