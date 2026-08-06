require "rails_helper"

RSpec.describe NightAudits::Resolutions::BlockerBookingIds do
  it "merges stored, business-date, and fresh blocker ids" do
    night_audit = instance_double(NightAudit, blocked_details: { "missing_folio" => [ { "booking_id" => 1 } ] })
    business_date = instance_double(HotelBusinessDate, blockers_snapshot: { "missing_folio" => [ { booking_id: 2 } ] })

    expect(described_class.call(
      night_audit: night_audit,
      business_date_record: business_date,
      blocker_type: "missing_folio",
      fresh_blocked_details: { "missing_folio" => [ { "booking_id" => 3 } ] }
    )).to eq([ 1, 2, 3 ])
  end
end
