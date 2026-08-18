# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::Bookings::GenerateTourismTaxVoucherRecords do
  subject(:records) { described_class.new(booking:, printed_by: staff).call }

  let(:arrival) { Date.new(2026, 9, 1) }
  let(:hotel) do
    create(:hotel,
      tin: "TIN-123",
      sst_registration_number: "SST-456",
      tourism_tax_registration_number: "TTX-789")
  end
  let(:staff) { create(:user, name: "Front Desk") }
  let(:room_type) { create(:room_type, hotel:, name: "Ocean Suite") }
  let(:booking) do
    create(:booking,
      hotel:,
      check_in: arrival,
      check_out: arrival + 3.days,
      guest_name: "Aisha Rahman",
      guest_country: "Singapore",
      guest_home_address: "12 Jalan Pantai",
      tourism_tax_amount: 30,
      tax_lines: [ { "type" => "tourism_tax", "amount" => "30.00" } ],
      tax_posting_snapshot: tourism_tax_snapshot)
  end
  let(:tourism_tax_snapshot) do
    3.times.to_h do |offset|
      date = (arrival + offset.days).iso8601
      [
        date,
        [ {
          "type" => "tourism_tax",
          "rate" => "10.00",
          "basis_amount" => 1,
          "amount" => "10.00",
          "currency" => "MYR",
          "stay_date" => date
        } ]
      ]
    end
  end

  before do
    create(:booking_room,
      booking:,
      room_type:,
      room_number: "204",
      room_type_snapshot: { "name" => "Ocean Suite" })
  end

  it "normalizes the payable voucher identity, parties, and room-night charge" do
    expect(records.hotel_identifier_line).to eq("TIN: TIN-123 · SST: SST-456 · Tourism Tax: TTX-789")
    expect(records.status_badge).to eq(label: "Payable", variant: :warning)
    expect(records.closing_note).to eq(described_class::PAYABLE_NOTE)
    expect(records.currency).to eq("MYR")
    expect(records.charge_rows.sole).to have_attributes(
      description: "Tourism tax",
      quantity: "3",
      rate: "10.00",
      amount: "30.00"
    )
    expect(records.party_blocks.first[:entries]).to include(
      [ "Name", "Aisha Rahman" ],
      [ "Nationality", "Singapore" ],
      [ "Address", "12 Jalan Pantai" ]
    )
    expect(records.party_blocks.second[:entries]).to include([ "Room", "Ocean Suite - 204" ])
    expect(records.party_blocks.third[:entries]).to include(
      [ "Status", "Payable" ],
      [ "Collected on", "Not yet collected" ],
      [ "Issued by", "Front Desk" ]
    )
  end

  it "reports when a tourism tax payment was collected" do
    folio = create(:booking_folio, booking:, hotel:, folio_number: 901)
    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: "payment",
      category: "cash",
      amount: 30,
      posting_date: Date.new(2026, 9, 4),
      metadata: { "tourism_tax" => true, "source" => "tourism_tax_checkout" })
    booking.update!(tourism_tax_collected: true)

    expect(records.status_badge).to eq(label: "Collected", variant: :positive)
    expect(records.closing_note).to eq(described_class::COLLECTED_NOTE)
    expect(records.party_blocks.third[:entries]).to include(
      [ "Status", "Collected" ],
      [ "Collected on", "04 Sep 2026" ]
    )
  end

  it "does not invent quantity or rate when a legacy booking has no posting snapshot" do
    booking.update!(tax_posting_snapshot: {})

    expect(records.charge_rows.sole).to have_attributes(
      description: "Tourism tax",
      quantity: nil,
      rate: nil,
      amount: "30.00"
    )
  end
end
