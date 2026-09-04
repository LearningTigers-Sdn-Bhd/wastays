# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::Bookings::GenerateReservationRecords do
  subject(:records) { described_class.new(booking: booking).call }

  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel:, name: "Ocean Suite") }
  let(:arrival) { Date.new(2026, 9, 1) }
  let(:booking) do
    create(
      :booking,
      hotel:,
      check_in: arrival,
      check_out: arrival + 3.days,
      total_amount: 648,
      currency: "MYR",
      guest_name: "Aisha Rahman",
      guest_home_address: guest_home_address,
      hotel_snapshot: {
        "property_policy" => {
          "check_in_time" => "3:00 PM",
          "check_out_time" => "11:00 AM",
          "cancellation_policy" => "No refund"
        }
      },
      tax_lines: [ { "name" => "SST", "amount" => "48.00" } ],
      tax_posting_snapshot: tax_posting_snapshot
    )
  end
  let(:guest_home_address) { "12 Jalan Pantai, Kota Kinabalu" }
  let(:nightly_prices) { [ 100, 200, 300 ] }
  let(:tax_posting_snapshot) do
    [ 8, 16, 24 ].each_with_index.to_h do |amount, index|
      [
        (arrival + index.days).iso8601,
        [ { "name" => "SST", "amount" => amount.to_s, "transaction_code_code" => "TX-SST" } ]
      ]
    end
  end

  before do
    create(
      :booking_room,
      booking:,
      room_type:,
      subtotal: nightly_prices.sum,
      room_type_snapshot: { "name" => "Ocean Suite" },
      nightly_rate_snapshot: nightly_prices.each_with_index.to_h do |price, index|
        [
          (arrival + index.days).iso8601,
          { "price" => price.to_s, "transaction_code_code" => "RM-DELUXE" }
        ]
      end
    )
  end

  it "builds invoice-style party blocks with the booking-time policy and guest address" do
    expect(records.party_blocks).to eq([
      {
        heading: "Guest details",
        entries: [
          [ "Guest", "Aisha Rahman" ],
          [ "Address", "12 Jalan Pantai, Kota Kinabalu" ],
          [ "Nationality", booking.guest_country ]
        ]
      },
      {
        heading: "Contact details",
        entries: [
          [ "Email", booking.guest_email ],
          [ "Phone", booking.guest_phone ]
        ]
      },
      {
        heading: "Stay details",
        entries: [
          [ "Booked at", HotelPortal::Reports::Exports::PdfTheme.format_time(booking.created_at, hotel.hotel_time_zone) ],
          [ "Arrival", "01 Sep 2026, 3:00 PM" ],
          [ "Departure", "04 Sep 2026, 11:00 AM" ],
          { columns: [ [ "Duration", "3 nights" ], [ "Guests", "2 adults" ] ] }
        ]
      }
    ])
  end

  # The voucher hands the frame the live hotel, and the frame is what names the ways of
  # reaching it. The records object carries no masthead contact line of its own.
  it "hands the masthead the hotel itself" do
    expect(records.hotel).to eq(hotel)
    expect(records).not_to respond_to(:hotel_contact_line)
  end

  it "always provides an address entry when the guest address is blank" do
    booking.update!(guest_home_address: nil)

    address = records.party_blocks.first.fetch(:entries).find { |label, _| label == "Address" }
    expect(address).to eq([ "Address", "Not provided" ])
  end

  it "creates one accommodation row and each non-tourism charge row for every night" do
    expect(records.charge_rows.map(&:description)).to eq([
      "Ocean Suite", "SST", "Ocean Suite", "SST", "Ocean Suite", "SST"
    ])

    room_rows = records.charge_rows.select { |row| row.description == "Ocean Suite" }
    expect(room_rows.map(&:secondary_description)).to eq([ "Night 1 of 3", "Night 2 of 3", "Night 3 of 3" ])
    expect(room_rows.map { |row| [ row.code, row.net, row.charges, row.gross ] }).to eq([
      [ "RM-DELUXE", 100.to_d, nil, 100.to_d ],
      [ "RM-DELUXE", 200.to_d, nil, 200.to_d ],
      [ "RM-DELUXE", 300.to_d, nil, 300.to_d ]
    ])

    tax_rows = records.charge_rows.select { |row| row.description == "SST" }
    expect(tax_rows.map { |row| [ row.code, row.net, row.charges, row.gross ] }).to eq([
      [ "TX-SST", nil, 8.to_d, 8.to_d ],
      [ "TX-SST", nil, 16.to_d, 16.to_d ],
      [ "TX-SST", nil, 24.to_d, 24.to_d ]
    ])
    expect(records.charge_rows.sum(0.to_d, &:gross)).to eq(records.total_due)
  end

  it "supports one-, three-, seven-, and fourteen-night snapshot breakdowns" do
    [ 1, 3, 7, 14 ].each do |night_count|
      booking.update!(check_out: arrival + night_count.days, total_amount: night_count * 100, tax_lines: [], tax_posting_snapshot: {})
      booking.booking_rooms.sole.update!(
        subtotal: night_count * 100,
        nightly_rate_snapshot: night_count.times.to_h do |index|
          [ (arrival + index.days).iso8601, { "price" => "100.00" } ]
        end
      )

      rows = described_class.new(booking: booking.reload).call.charge_rows
      expect(rows.size).to eq(night_count)
      expect(rows.last.secondary_description).to eq("Night #{night_count} of #{night_count}")
    end
  end

  it "uses aggregate rows without averaging when a legacy nightly snapshot is incomplete" do
    booking.booking_rooms.sole.update!(nightly_rate_snapshot: { arrival.iso8601 => { "price" => "100.00" } })
    booking.update!(tax_posting_snapshot: {})

    expect(records.charge_rows.map(&:description)).to eq([ "Ocean Suite", "SST" ])
    expect(records.charge_rows.first).to have_attributes(
      date: "01 Sep 2026",
      secondary_description: "3 nights | Nightly breakdown unavailable",
      net: 600.to_d,
      gross: 600.to_d
    )
    expect(records.charge_rows.second).to have_attributes(charges: 48.to_d, gross: 48.to_d)
  end

  it "excludes tourism tax from charges and discloses whether it is payable or collected" do
    tourism_line = { "name" => "Tourism tax", "type" => "tourism_tax", "amount" => "30.00" }
    booking.update!(
      tax_lines: booking.tax_lines + [ tourism_line ],
      tax_posting_snapshot: booking.tax_posting_snapshot.transform_values { |lines| lines + [ tourism_line.merge("amount" => "10.00") ] },
      tourism_tax_amount: 30,
      tourism_tax_collected: false
    )

    expect(records.charge_rows.map(&:description)).not_to include("Tourism tax")
    expect(records.total_due).to eq(648.to_d)
    expect(records.tourism_tax_disclosure).to eq(
      "Excluded from booking total: Tourism tax of MYR 30.00 is payable at the property. " \
        "A separate tourism tax voucher will be provided."
    )

    booking.update!(tourism_tax_collected: true)
    expect(described_class.new(booking: booking.reload).call.tourism_tax_disclosure).to eq(
      "Excluded from booking total: Tourism tax of MYR 30.00 was collected separately. " \
        "See the official tourism tax voucher."
    )
  end

  it "formats alternate currency amounts and groups the financial summary" do
    booking.update!(currency: "SGD")

    expect(records.money(1234.5)).to eq("1,234.50")
    expect(records.summary_rows.map { |row| [ row.label, row.amount ] }).to include(
      [ "Accommodation", 600.to_d ],
      [ "SST", 48.to_d ],
      [ "Balance due", 648.to_d ]
    )
  end

  it "includes active payment references while filtering reversal noise" do
    folio = create(:booking_folio, booking:, hotel:)
    reversed = create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: :payment,
      category: "booking_payment",
      amount: 100,
      metadata: { "payment_source" => "card", "receipt_reference" => "RCP-OLD" }
    )
    reversal = create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: :adjustment,
      category: "correction",
      amount: -100,
      reversal_of_transaction_id: reversed.id
    )
    reversed.update_column(:voided_by_transaction_id, reversal.id)
    create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: :payment,
      category: "booking_payment",
      amount: 200,
      posting_date: Date.new(2026, 9, 2),
      metadata: { "payment_source" => "bank", "receipt_reference" => "RCP-NEW" }
    )

    expect(records.payment_rows.size).to eq(1)
    expect(records.payment_rows.first).to have_attributes(
      date: "02 Sep 2026",
      code: "BANK",
      description: "Payment - Bank Transfer",
      secondary_description: "Receipt: RCP-NEW",
      amount: 200.to_d
    )
    expect(records.total_payments).to eq(200.to_d)
    expect(records.balance).to eq(448.to_d)
  end

  it "reports an overpayment as a credit balance instead of hiding it as settled" do
    folio = create(:booking_folio, booking:, hotel:)
    create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: :payment,
      category: "booking_payment",
      amount: 700
    )

    expect(records.balance).to eq(-52.to_d)
    expect(records.balance_label).to eq("Credit balance")
    expect(records.summary_rows.last).to have_attributes(label: "Credit balance", amount: 52.to_d, variant: :subtotal)
  end

  it "maps booking statuses to shared badge variants" do
    {
      "confirmed" => :positive,
      "checked_in" => :positive,
      "completed" => :positive,
      "cancelled" => :danger,
      "voided" => :danger,
      "no_show" => :danger,
      "pending" => :warning,
      "no_show_detected" => :warning,
      "due_out_detected" => :warning,
      "checkout_required" => :warning,
      "overbooked" => :warning
    }.each do |status, variant|
      booking.update_column(:status, status)
      expect(described_class.new(booking: booking.reload).call.status_badge).to eq(label: status.humanize, variant: variant)
    end

    allow(booking).to receive(:status).and_return("manual_review")
    expect(described_class.new(booking: booking).call.status_badge).to eq(label: "Manual review", variant: :neutral)
  end
end
