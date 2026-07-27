# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightAudits::CompletedNightlyChargeReview do
  let(:business_date) { Date.new(2026, 7, 25) }
  let(:hotel) { create(:hotel, time_zone: "Kuala Lumpur") }
  let(:zone) { hotel.hotel_time_zone }
  let(:night_audit) { create(:night_audit, hotel: hotel, business_date: business_date, status: "completed") }

  it "previews a missing hotel-local final-night line without writing to the ledger" do
    booking = create(:booking,
      hotel: hotel,
      status: "completed",
      check_in: zone.local(2026, 7, 23, 0, 0),
      check_out: zone.local(2026, 7, 26, 0, 0),
      checked_out_at: zone.local(2026, 7, 26, 0, 0))
    create(:booking_room,
      booking: booking,
      subtotal: 30,
      nightly_rate_snapshot: { business_date.iso8601 => { "price" => "10.00" } })
    create(:booking_folio, booking: booking, hotel: hotel)

    expect { @entries = described_class.call(night_audit: night_audit) }.not_to change(FolioTransaction, :count)

    entry = @entries.sole
    expect(entry.booking).to eq(booking)
    expect(entry.expected_total).to eq(10.to_d)
    expect(entry.issues.sole["issue_types"]).to include("missing")
  end

  it "does not report the UTC date before local arrival" do
    prior_audit = create(:night_audit, hotel: hotel, business_date: business_date - 3.days, status: "completed")
    booking = create(:booking,
      hotel: hotel,
      status: "completed",
      check_in: zone.local(2026, 7, 23, 0, 0),
      check_out: zone.local(2026, 7, 26, 0, 0),
      checked_out_at: zone.local(2026, 7, 26, 0, 0))
    create(:booking_room, booking: booking, subtotal: 30)
    create(:booking_folio, booking: booking, hotel: hotel)

    expect(described_class.call(night_audit: prior_audit)).to be_empty
  end
end
