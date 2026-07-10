# frozen_string_literal: true

require "rails_helper"

RSpec.describe FolioRouting::RefreshBookingForecasts do
  it "rebuilds booking tax snapshots from room items and syncs the primary folio" do
    booking = create(:booking, guest_country: "Malaysia")
    room = create(:booking_room, booking: booking, nightly_rate_snapshot: { "2026-07-09" => 150 })
    folio = create(:booking_folio, booking: booking, hotel: booking.hotel)
    snapshot = OpenStruct.new(
      tax_lines: [ { "type" => "sst", "amount" => "12.00" } ],
      tax_posting_snapshot: { "room_revenue" => { "taxes" => [ "sst" ] } }
    )
    builder = instance_double(Bookings::BuildFinancialSnapshot, call: snapshot)
    allow(Bookings::BuildFinancialSnapshot).to receive(:new).and_return(builder)
    allow(Folios::SyncForecastedCharges).to receive(:call)

    described_class.call(booking: booking)

    expect(Bookings::BuildFinancialSnapshot).to have_received(:new).with(
      hotel: booking.hotel,
      booking: booking,
      check_in: booking.check_in,
      check_out: booking.check_out,
      guest_country: "Malaysia",
      room_items: [ { quantity: 1, nightly_rate_snapshot: room.nightly_rate_snapshot } ]
    )
    expect(booking.reload.tax_lines).to eq([ { "type" => "sst", "amount" => "12.00" } ])
    expect(booking.tax_posting_snapshot).to eq("room_revenue" => { "taxes" => [ "sst" ] })
    expect(Folios::SyncForecastedCharges).to have_received(:call).with(booking_folio: folio)
  end

  it "updates snapshots without syncing when no folio exists" do
    booking = create(:booking)
    create(:booking_room, booking: booking, nightly_rate_snapshot: { "2026-07-09" => 100 })
    snapshot = OpenStruct.new(tax_lines: [], tax_posting_snapshot: {})
    allow(Bookings::BuildFinancialSnapshot).to receive(:new).and_return(instance_double(Bookings::BuildFinancialSnapshot, call: snapshot))
    allow(Folios::SyncForecastedCharges).to receive(:call)

    described_class.call(booking: booking)

    expect(booking.reload.tax_lines).to eq([])
    expect(Folios::SyncForecastedCharges).not_to have_received(:call)
  end
end
