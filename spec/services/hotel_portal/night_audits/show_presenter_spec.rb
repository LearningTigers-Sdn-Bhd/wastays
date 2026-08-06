require "rails_helper"

RSpec.describe HotelPortal::NightAudits::ShowPresenter do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, name: "Platform Admin") }
  let(:business_date) { Date.new(2026, 6, 13) }
  let(:started_at) { Time.zone.local(2026, 6, 14, 8, 44, 0) }
  let(:completed_at) { started_at + 30.seconds }
  let(:night_audit) do
    create(:night_audit,
      hotel: hotel,
      performed_by_user: user,
      business_date: business_date,
      status: status,
      started_at: started_at,
      completed_at: completed_at,
      summary: summary,
      blocked_details: blocked_details,
      exceptions: exceptions)
  end
  let(:status) { "completed" }
  let(:summary) do
    {
      "arrivals_count" => 1,
      "due_out_count" => 2,
      "checked_out_count" => 3,
      "in_house_count" => 4,
      "payment_status_counts" => { "captured" => 6, "authorized" => 1 },
      "run_results" => {
        "status_changes" => {
          "count" => 1,
          "items" => [ { "confirmation_token" => "ABC123", "from" => "checked_in", "to" => "due_out_detected" } ]
        },
        "charges_posted" => { "count" => 0, "total" => "0", "items" => [] }
      }
    }
  end
  let(:blocked_details) { {} }
  let(:exceptions) { {} }
  let(:adjustments) { [] }

  subject(:presenter) do
    described_class.new(
      night_audit: night_audit,
      adjustments: adjustments,
      view_context: ApplicationController.helpers
    )
  end

  it "builds a completed audit receipt with stable display data" do
    create(:night_audit_financial_summary,
      night_audit: night_audit,
      room_revenue: 100,
      tax_revenue: 10,
      no_show_charges: 5,
      refunds_total: 2,
      payments_total: 113,
      adjustments_total: 3)

    expect(presenter.title).to eq("Night Audit / 13 Jun 2026")
    expect(presenter.subtitle).to include("Completed", "Manual", "Platform Admin")
    expect(presenter.status_tone).to eq("success")
    expect(presenter.result_banner[:title]).to eq("Date closed")
    expect(presenter.audit_details.map(&:label)).to include("Business Date", "Duration", "Audit Packet")
    expect(presenter.audit_details.find { |row| row.label == "Duration" }.value).to eq("< 1 minute")
    expect(presenter.audit_snapshot.map(&:value)).to eq([ 1, 2, 3, 4, 0, 0 ])
    expect(presenter.audit_snapshot.map(&:icon)).to eq(%w[log-in log-out circle-check bed-double triangle-alert circle-alert])
    expect(presenter.payment_status_counts.map(&:label)).to eq([ "Partial", "Pending", "Captured", "Failed", "Refunded", "Voided", "Authorized" ])
    expect(presenter.payment_status_counts.last.value).to eq(1)
    expect(presenter.net_revenue).to eq("$113.00")
    expect(presenter.run_result_rows.sole.details).to eq("checked_in → due_out_detected")
    expect(presenter.audit_packet_visible?).to be(true)
  end

  it "preserves notes in the full-width audit details row" do
    night_audit.update!(notes: "Closed after manager review")

    notes = presenter.audit_details.last
    expect(notes.label).to eq("Notes")
    expect(notes.value).to eq("Closed after manager review")
    expect(notes.wide?).to be(true)
  end

  it "presents force-closed audits as exceptional" do
    night_audit.update!(force_closed: true)

    expect(presenter.status_label).to eq("Force Closed")
    expect(presenter.status_tone).to eq("danger")
    expect(presenter.result_banner[:title]).to eq("Date force closed")
  end

  context "when blocked" do
    let(:status) { "blocked" }
    let(:blocked_details) do
      { "missing_folio" => [ { "guest_name" => "Aisha Tan", "confirmation_token" => "BLOCK-1", "reason" => "Folio required" } ] }
    end

    it "builds blocker evidence and exposes the resolve action" do
      expect(presenter.result_banner[:title]).to eq("Cannot close this date")
      expect(presenter.blocker_rows.sole.type).to eq("Accounting blocker")
      expect(presenter.resolve_blockers_visible?).to be(true)
      expect(presenter.audit_packet_visible?).to be(false)
    end
  end

  context "when failed" do
    let(:status) { "failed" }

    it "uses failure copy and tone" do
      expect(presenter.status_tone).to eq("danger")
      expect(presenter.result_banner[:title]).to eq("Night Audit failed")
    end
  end

  context "when running" do
    let(:status) { "running" }
    let(:completed_at) { nil }

    it "exposes refresh state and in-progress duration" do
      expect(presenter.auto_refresh?).to be(true)
      expect(presenter.result_banner[:title]).to eq("Night Audit in progress")
      expect(presenter.audit_details.find { |row| row.label == "Duration" }.value).to eq("In progress")
    end
  end

  context "when pending" do
    let(:status) { "pending" }
    let(:started_at) { nil }
    let(:completed_at) { nil }

    it "uses neutral pending copy" do
      expect(presenter.status_tone).to eq("neutral")
      expect(presenter.result_banner[:title]).to eq("Audit pending")
    end
  end

  it "provides compact empty states when optional records are missing" do
    expect(presenter.financial_rows).to be_empty
    expect(presenter.manual_adjustment_rows).to be_empty
    expect(presenter.manual_adjustments_open?).to be(false)
    expect(presenter.empty_state(:financial)).to include("No financial summary")
  end
end
