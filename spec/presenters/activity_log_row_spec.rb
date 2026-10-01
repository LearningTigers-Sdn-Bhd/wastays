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

  it "maps a night audit step" do
    log = NightAuditLog.create!(hotel: create(:hotel), night_audit: create(:night_audit), action_type: "process_started", message: "Started")

    expect(described_class.for("night_audits", log)).to have_attributes(who: "System", event: "Process started", summary: "Started", details: "Business date #{log.night_audit.business_date}")
  end

  it "maps an onboarding event" do
    event = OnboardingAuditEvent.create!(hotel: create(:hotel), event_type: "approved", section_key: Onboarding::SectionCatalog.keys.first, occurred_at: Time.current)

    expect(described_class.for("onboarding", event)).to have_attributes(who: "System", event: "Approved", time: event.occurred_at)
  end

  it "maps a room change with its status move and reason" do
    log = create(:room_operational_audit_log, room_number: "101", old_status: "dirty", new_status: "ready", reason: "Inspected")

    expect(described_class.for("rooms", log)).to have_attributes(details: "Room 101", summary: "Dirty -> Ready. Inspected", event: "Room status changed")
  end

  it "maps a financial event and names the source when no one acted" do
    event = create(:financial_audit_event, event_type: "business_date_closed", source: "night_audit")

    expect(described_class.for("financial", event)).to have_attributes(who: "Night Audit", event: "Business date closed", details: "Business date #{event.business_date}")
  end
end
