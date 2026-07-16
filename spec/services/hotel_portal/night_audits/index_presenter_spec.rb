require "rails_helper"

RSpec.describe HotelPortal::NightAudits::IndexPresenter do
  include ActiveSupport::Testing::TimeHelpers

  let(:account) { create(:account) }
  let(:hotel) do
    create(:hotel,
      :without_current_business_date,
      account: account,
      time_zone: "Kuala Lumpur",
      business_starts_at: "08:00",
      business_ends_at: "02:00")
  end
  let(:user) { create(:user, account: account) }
  let(:business_date) { Date.new(2026, 6, 12) }
  let(:business_date_record) { create(:hotel_business_date, hotel: hotel, business_date: business_date, status: business_date_status) }
  let(:business_date_status) { "open" }
  let(:evaluation) do
    {
      blocked_details: blocked_details,
      exceptions: exceptions,
      summary: {
        "arrivals_count" => 2,
        "review_no_show_count" => 1,
        "due_out_count" => 3
      }
    }
  end
  let(:blocked_details) { {} }
  let(:exceptions) { {} }
  let(:night_audits) { NightAudit.where(hotel: hotel).recent_first.page(1).per(25) }

  subject(:presenter) do
    described_class.new(
      hotel: hotel,
      current_user: user,
      business_date_record: business_date_record,
      evaluation: evaluation,
      night_audits: night_audits
    )
  end

  before do
    allow(user).to receive(:has_permission?).with("override_financial_date_lock", hotel: hotel).and_return(false)
  end

  it "shows an open current business date as the audit authority" do
    travel_to Time.find_zone("Kuala Lumpur").local(2026, 6, 13, 1, 0) do
      expect(presenter.ui_state).to eq("OPEN")
      expect(presenter.business_date_status_label).to eq("Open")
      expect(presenter.business_date_status_badge_class).to include("bg-blue-50")
      expect(presenter.current_business_date_label).to eq("12 Jun 2026")
      expect(presenter.calendar_date_label).to eq("13 Jun 2026")
      expect(presenter.hotel_timezone_label).to eq("Kuala Lumpur")
      expect(presenter.date_explanation).to include("Calendar date is 13 Jun 2026")
      expect(presenter.date_explanation).to include("hotel remains on business date 12 Jun 2026")
    end
  end

  it "derives ready for audit when the open date is closable and clear" do
    travel_to Time.find_zone("Kuala Lumpur").local(2026, 6, 13, 10, 0) do
      expect(presenter.ui_state).to eq("READY_FOR_AUDIT")
      expect(presenter.status_label).to eq("Ready for Audit")
      expect(presenter.primary_action.label).to eq("Run Audit")
    end
  end

  context "with operational readiness items" do
    let(:blocked_details) do
      {
        "due_out_not_checked_out" => [
          {
            "booking_id" => 123,
            "confirmation_token" => "WS-123",
            "guest_name" => "Aisha Tan",
            "status" => "checked_in",
            "reason" => "Due out today but still not checked out"
          }
        ]
      }
    end
    let(:exceptions) do
      {
        "review_due_out" => [
          { "booking_id" => 456, "reason" => "Due-out review carried forward" }
        ]
      }
    end

    it "builds compact readiness and blocker rows with booking actions" do
      expect(presenter.review_queue_value).to eq("1 / 1")

      readiness_row = presenter.readiness_detail_rows.find { |row| row.type == "Due out not checked out" }
      expect(readiness_row.count).to eq(1)
      expect(readiness_row.summary).to eq("1 item requiring attention before close.")
      expect(readiness_row.action).to eq("booking")
      expect(readiness_row.booking_id).to eq(123)

      blocker_row = presenter.flattened_blocker_rows.sole
      expect(blocker_row.reason).to eq("Due out today but still not checked out")
      expect(blocker_row.detail).to eq("Aisha Tan · WS-123 · Checked in")
      expect(blocker_row.action).to eq("booking")
      expect(blocker_row.booking_id).to eq(123)
    end
  end

  context "when due-out reviews are the only unresolved items" do
    let(:exceptions) do
      {
        "review_due_out" => [
          { "booking_id" => 123, "reason" => "Late checkout requires staff review" }
        ]
      }
    end

    it "presents them as non-blocking warnings" do
      travel_to Time.find_zone("Kuala Lumpur").local(2026, 6, 13, 10, 0) do
        expect(presenter.ui_state).to eq("READY_FOR_AUDIT")
        expect(presenter.readiness_counters.find { |counter| counter.label == "Blockers" }.value).to eq(0)
        expect(presenter.readiness_counters.find { |counter| counter.label == "Warnings" }.value).to eq(1)
        expect(presenter.warning_groups.sole.label).to eq("Due-Out Review")
        expect(presenter.primary_action.enabled).to be(true)
      end
    end
  end

  context "when audit is running" do
    let(:business_date_status) { "audit_running" }

    before do
      create(:night_audit, hotel: hotel, business_date: business_date, status: "running")
    end

    it "exposes running state and prevents duplicate runs" do
      expect(presenter.ui_state).to eq("AUDIT_RUNNING")
      expect(presenter.status_label).to eq("Audit Running")
      expect(presenter.business_date_status_label).to eq("Audit running")
      expect(presenter.business_date_status_badge_class).to include("bg-sky-50")
      expect(presenter.primary_action.label).to eq("Refresh Status")
    end
  end

  context "when audit is blocked" do
    let(:business_date_status) { "audit_blocked" }

    before do
      create(:night_audit, hotel: hotel, business_date: business_date, status: "blocked")
    end

    it "exposes blocker recovery actions" do
      expect(presenter.ui_state).to eq("AUDIT_BLOCKED")
      expect(presenter.status_label).to eq("Audit Blocked")
      expect(presenter.business_date_status_label).to eq("Audit blocked")
      expect(presenter.business_date_status_badge_class).to include("bg-amber-50")
      expect(presenter.resolve_action.label).to eq("Resolve Blockers")
      expect(presenter.primary_action.label).to eq("Retry Audit")
    end

    context "with blocker details" do
      let(:blocked_details) do
        {
          "missing_folio" => [
            { "booking_id" => 123, "reason" => "Booking requires a folio before night audit can close" }
          ]
        }
      end

      it "prioritizes the run-level resolve action for blocker rows" do
        expect(presenter.readiness_detail_rows.first.action).to eq("resolve")
        expect(presenter.flattened_blocker_rows.first.action).to eq("resolve")
      end
    end
  end

  context "when the last audit failed" do
    before do
      create(:night_audit, hotel: hotel, business_date: business_date, status: "failed")
    end

    it "uses retry copy instead of ready copy" do
      expect(presenter.ui_state).to eq("AUDIT_FAILED")
      expect(presenter.status_label).to eq("Audit Can Be Retried")
      expect(presenter.primary_action.label).to eq("Retry Audit")
    end
  end

  it "formats closed audit history rows" do
    audit = create(:night_audit, hotel: hotel, business_date: business_date - 1.day, status: "completed")

    row = presenter.history_rows.find { |history_row| history_row.night_audit == audit }

    expect(row.status_label).to eq("Completed")
    expect(row.finished_at).to include("2026")
  end

  it "formats force-closed audit history rows as exceptional" do
    audit = create(:night_audit, hotel: hotel, business_date: business_date - 1.day, status: "completed", force_closed: true)

    row = presenter.history_rows.find { |history_row| history_row.night_audit == audit }

    expect(row.status_label).to eq("Force Closed")
    expect(row.exceptional?).to be(true)
  end

  context "with closed business-date states" do
    it "presents a completed close as successful" do
      business_date_record.update!(status: "closed")

      expect(presenter.business_date_status_label).to eq("Closed")
      expect(presenter.business_date_status_badge_class).to include("bg-emerald-50")
    end

    it "presents a force close as dangerous" do
      business_date_record.update!(status: "force_closed")

      expect(presenter.business_date_status_label).to eq("Force closed")
      expect(presenter.business_date_status_badge_class).to include("bg-red-50")
    end
  end

  it "presents a missing business-date record neutrally" do
    presenter_without_record = described_class.new(
      hotel: hotel,
      current_user: user,
      business_date_record: nil,
      evaluation: evaluation,
      night_audits: night_audits
    )

    expect(presenter_without_record.business_date_status_label).to eq("Not initialized")
    expect(presenter_without_record.business_date_status_badge_class).to include("bg-muted", "text-muted-foreground")
  end

  context "when force close is permitted and eligible" do
    let(:business_date_status) { "audit_blocked" }

    before do
      allow(user).to receive(:has_permission?).with("override_financial_date_lock", hotel: hotel).and_return(true)
    end

    it "exposes force close confirmation copy" do
      expect(presenter.can_force_close?).to be(true)
      expect(presenter.force_close_confirmation).to include("advance the hotel business date")
      expect(presenter.force_close_confirmation).to include("without resolving all blockers")
    end
  end
end
