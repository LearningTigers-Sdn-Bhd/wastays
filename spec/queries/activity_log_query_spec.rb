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
end
