# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightAudits::RepairCompletedNightlyCharges do
  let(:business_date) { Date.new(2026, 7, 25) }
  let(:hotel) { create(:hotel, time_zone: "Kuala Lumpur") }
  let(:zone) { hotel.hotel_time_zone }
  let(:actor) { create(:user, account: hotel.account) }
  let(:night_audit) { create(:night_audit, hotel: hotel, business_date: business_date, status: "completed", performed_by_user: actor) }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      status: "completed",
      check_in: zone.local(2026, 7, 23, 0, 0),
      check_out: zone.local(2026, 7, 26, 0, 0),
      checked_out_at: zone.local(2026, 7, 26, 0, 0))
  end
  let!(:room) do
    create(:booking_room,
      booking: booking,
      subtotal: 30,
      nightly_rate_snapshot: { business_date.iso8601 => { "price" => "10.00" } })
  end
  let!(:folio) { create(:booking_folio, booking: booking, hotel: hotel, status: "closed", closed_at: Time.current) }

  before do
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date + 1.day)
    create(:hotel_business_date, hotel: hotel, business_date: business_date, status: "closed")
    create(:night_audit_financial_summary, night_audit: night_audit, room_revenue: 0)
    allow(actor).to receive(:has_permission?).with("manage_night_audit", hotel: hotel).and_return(true)
    allow(actor).to receive(:has_permission?).with("override_financial_date_lock", hotel: hotel).and_return(true)
  end

  it "repairs selected lines and atomically refreshes accounting evidence" do
    result = described_class.call(
      night_audit: night_audit,
      booking: booking,
      actor: actor,
      reason: "Room charge omitted by timezone defect"
    )

    expect(result).to be_success
    charge = result.posted_transactions.sole
    expect(charge.amount).to eq(10.to_d)
    expect(charge.posting_date).to eq(business_date)
    expect(charge.metadata["posting_source"]).to eq("historical_nightly_charge_repair")
    expect(charge.metadata["stay_date"]).to eq(business_date.iso8601)
    expect(night_audit.reload).to be_completed
    expect(night_audit.financial_summary.reload.room_revenue).to eq(10.to_d)
    expect(hotel.journal_batches.find_by!(business_date: business_date).status).to eq("finalized")
    expect(FolioOperationLog.where(booking: booking, operation_type: "correction")).to exist
    expect(NightAuditLog.where(night_audit: night_audit, action_type: "completed_audit_repair")).to exist
    expect(FinancialAuditEvent.where(folio_transaction: charge, event_type: "closed_date_override_posted")).to exist
  end

  it "requires both permissions and a reason" do
    allow(actor).to receive(:has_permission?).with("override_financial_date_lock", hotel: hotel).and_return(false)

    result = described_class.call(night_audit: night_audit, booking: booking, actor: actor, reason: "Needed")
    expect(result).not_to be_success
    expect(result.error).to include("closed business date")

    allow(actor).to receive(:has_permission?).with("override_financial_date_lock", hotel: hotel).and_return(true)
    result = described_class.call(night_audit: night_audit, booking: booking, actor: actor, reason: "")
    expect(result).not_to be_success
    expect(result.error).to eq("A correction reason is required.")
  end

  it "is idempotent after repair" do
    described_class.call(night_audit: night_audit, booking: booking, actor: actor, reason: "First repair")

    expect {
      @result = described_class.call(night_audit: night_audit, booking: booking, actor: actor, reason: "Retry repair")
    }.not_to change(FolioTransaction, :count)

    expect(@result).to be_success
    expect(@result).to be_already_repaired
  end

  it "rolls the ledger repair back when journal rebuilding fails" do
    allow(Financials::CreateJournalBatch).to receive(:call).and_raise("journal failed")

    expect {
      @result = described_class.call(night_audit: night_audit, booking: booking, actor: actor, reason: "Repair with failure")
    }.not_to change(FolioTransaction, :count)

    expect(@result).not_to be_success
    expect(@result.error).to eq("journal failed")
    expect(night_audit.financial_summary.reload.room_revenue).to eq(0.to_d)
  end
end
