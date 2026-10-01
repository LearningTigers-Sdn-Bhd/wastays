require "rails_helper"

RSpec.describe ActivityLogRow do
  it "maps an inventory change" do
    log = create(:inventory_audit_log, action_type: "rate_update", old_value: { "date" => "2026-04-01", "price" => 100, "currency" => "MYR" }, new_value: { "date" => "2026-04-01", "price" => 120, "currency" => "MYR" })

    row = described_class.for("inventory", log)

    expect(row).to have_attributes(who: log.user.name, event: "Rate Update", details: log.room_type.name, summary: "2026-04-01: MYR 100 -> MYR 120")
    expect(row.detail.keys).to eq(%i[old_value new_value metadata])
  end

  it "maps a booking change and names the platform when no staff acted" do
    log = create(:booking_audit_log, user: nil, source: "system", action_type: "check_in")

    row = described_class.for("bookings", log)

    expect(row).to have_attributes(who: "System", event: "Checked In", details: "Booking", time: log.occurred_at)
  end

  it "maps a folio operation" do
    log = create(:folio_operation_log, actor: nil, operation_type: "close_folio", reason: "Month end")

    row = described_class.for("folios", log)

    expect(row).to have_attributes(who: "System", event: "Close folio", details: log.booking.confirmation_token, summary: "Month end")
    expect(row.detail).to include(reason: "Month end")
  end
end
