require "rails_helper"

RSpec.describe ActivityLogQuery do
  let(:hotel) { create(:hotel) }
  let(:other_hotel) { create(:hotel) }
  let(:staff) { create(:user, name: "Sam Staff #{SecureRandom.hex(3)}") }
  let!(:inventory) { create(:inventory_audit_log, hotel: hotel, user: staff, action_type: "rate_update", created_at: Time.zone.local(2026, 9, 1, 10)) }
  let!(:other_inventory) { create(:inventory_audit_log, hotel: other_hotel, action_type: "inventory_update", created_at: Time.zone.local(2026, 9, 20, 10)) }
  let!(:booking_log) { create(:booking_audit_log, hotel: hotel, action_type: "check_in") }
  let!(:folio_log) { create(:folio_operation_log, booking: create(:booking, hotel: hotel), reason: "Guest dispute") }

  def result(params) = described_class.new(params).call.to_a

  it "defaults to the inventory tab and ignores unknown tabs" do
    expect(described_class.new({}).tab).to eq("inventory")
    expect(described_class.new(tab: "bogus").tab).to eq("inventory")
  end

  it "reads one table per tab, newest first" do
    expect(result({})).to eq([ other_inventory, inventory ])
    expect(result(tab: "bookings")).to eq([ booking_log ])
    expect(result(tab: "folios")).to eq([ folio_log ])
  end

  it "filters by hotel" do
    expect(result(hotel_id: hotel.id)).to eq([ inventory ])
  end

  it "filters by date range" do
    expect(result(range: "2026-09-10/2026-09-30")).to eq([ other_inventory ])
  end

  it "searches inventory by event and staff name" do
    expect(result(q: "rate_update")).to eq([ inventory ])
    expect(result(q: staff.name)).to eq([ inventory ])
  end

  it "searches bookings by event" do
    expect(result(tab: "bookings", q: "check_in")).to eq([ booking_log ])
    expect(result(tab: "bookings", q: "no-match-xyz")).to be_empty
  end

  it "searches folios by reason and booking token" do
    expect(result(tab: "folios", q: "dispute")).to eq([ folio_log ])
    expect(result(tab: "folios", q: folio_log.booking.confirmation_token)).to eq([ folio_log ])
  end

  describe "the other tabs" do
    let!(:night_log) { NightAuditLog.create!(hotel: hotel, night_audit: create(:night_audit, hotel: hotel), action_type: "blocker_found", message: "Open request left") }
    let!(:onboarding_event) { OnboardingAuditEvent.create!(hotel: hotel, user: staff, event_type: "submitted", section_key: Onboarding::SectionCatalog.keys.first, occurred_at: Time.current) }
    let!(:room_log) { create(:room_operational_audit_log, hotel: hotel, room_number: "A-77", reason: "Deep clean") }
    let!(:financial) { create(:financial_audit_event, hotel: hotel, event_type: "business_date_closed", reason: "Month end close", source: "night_audit") }

    it "reads one table per tab" do
      expect(result(tab: "night_audits")).to eq([ night_log ])
      expect(result(tab: "onboarding")).to eq([ onboarding_event ])
      expect(result(tab: "rooms")).to eq([ room_log ])
      expect(result(tab: "financial")).to eq([ financial ])
    end

    it "searches each tab" do
      expect(result(tab: "night_audits", q: "open request")).to eq([ night_log ])
      expect(result(tab: "onboarding", q: staff.name)).to eq([ onboarding_event ])
      expect(result(tab: "rooms", q: "A-77")).to eq([ room_log ])
      expect(result(tab: "financial", q: "month end")).to eq([ financial ])
      expect(result(tab: "financial", q: "no-match-xyz")).to be_empty
    end

    it "filters each tab by hotel and date range" do
      expect(result(tab: "rooms", hotel_id: other_hotel.id)).to be_empty
      expect(result(tab: "financial", hotel_id: hotel.id, range: "#{Date.current}/#{Date.current}")).to eq([ financial ])
      expect(result(tab: "onboarding", range: "2020-01-01/2020-01-02")).to be_empty
    end
  end
end
