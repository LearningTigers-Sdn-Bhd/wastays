require "rails_helper"

RSpec.describe HotelOps::RunNightAudit do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account) }
  let(:user) { create(:user, account: account, role: "hotel_staff") }
  let(:business_date) { Date.current }

  subject(:run_audit) do
    described_class.new(
      hotel: hotel,
      business_date: business_date,
      performed_by_user: user,
      trigger_mode: trigger_mode,
      notes: "Close of day"
    ).call
  end

  let(:trigger_mode) { "manual" }

  before do
    create(:booking,
      hotel: hotel,
      status: "confirmed",
      payment_status: "captured",
      check_in: business_date,
      check_out: business_date + 1.day)
    create(:booking,
      hotel: hotel,
      status: "completed",
      payment_status: "pending",
      check_in: business_date - 1.day,
      check_out: business_date,
      checked_in_at: business_date.beginning_of_day,
      checked_out_at: business_date.noon)
  end

  it "creates a completed night audit with payment summary and logs milestones" do
    expect { run_audit }.to change(NightAudit, :count).by(1)
                      .and change(NightAuditLog, :count).by(2) # process_started, completed

    night_audit = run_audit.night_audit

    expect(run_audit.success?).to be(true)
    expect(night_audit).to be_completed
    
    logs = night_audit.night_audit_logs
    expect(logs.first.action_type).to eq("process_started")
    expect(logs.last.action_type).to eq("completed")
  end

  it "blocks and logs when a due-out booking is not checked out" do
    create(:booking,
      hotel: hotel,
      status: "checked_in",
      payment_status: "captured",
      check_in: business_date - 1.day,
      check_out: business_date,
      checked_in_at: 1.day.ago)

    expect { run_audit }.to change(NightAuditLog, :count).by(3) # process_started, blocker_found, blocker_found (as finished status)

    result = run_audit

    expect(result.success?).to be(false)
    expect(result.night_audit).to be_blocked
    
    log = result.night_audit.night_audit_logs.find_by(action_type: "blocker_found")
    expect(log.message).to include("Found 1 blockers of type: Due out not checked out")
    expect(log.metadata["items"].first["confirmation_token"]).to be_present
  end

  it "stores open requests as warnings and logs exceptions" do
    booking = hotel.bookings.first
    create(:housekeeping_request, booking: booking, status: "pending")
    create(:complaint_request, booking: booking, status: "in_progress")

    expect { run_audit }.to change(NightAuditLog, :count).by(4) # started, exception, exception, completed

    result = run_audit

    expect(result.night_audit).to be_completed
    
    expect(result.night_audit.night_audit_logs.where(action_type: "exception_found").count).to eq(2)
  end

  it "supports scheduled runs without a user" do
    result = described_class.new(
      hotel: hotel,
      business_date: business_date,
      performed_by_user: nil,
      trigger_mode: "scheduled"
    ).call

    expect(result.success?).to be(true)
    expect(result.night_audit.trigger_mode).to eq("scheduled")
    expect(result.night_audit.performed_by_user).to be_nil
  end

  it "rejects rerun when the audit is already completed" do
    create(:night_audit, hotel: hotel, business_date: business_date, status: "completed")

    result = run_audit

    expect(result.success?).to be(false)
    expect(result.error).to eq("Night audit has already been completed for this date.")
  end

  it "reuses the same blocked audit row on rerun" do
    existing = create(:night_audit, hotel: hotel, business_date: business_date, status: "blocked", summary: { "old" => true })

    result = run_audit

    expect(result.night_audit.id).to eq(existing.id)
    expect(result.night_audit.summary).not_to eq("old" => true)
  end

  it "marks the audit failed and logs error when processing raises" do
    allow_any_instance_of(described_class).to receive(:build_summary).and_raise(StandardError, "boom")

    expect { run_audit }.to change(NightAuditLog, :count).by(2) # process_started, failed

    result = run_audit

    expect(result.success?).to be(false)
    expect(result.error).to eq("boom")
    expect(result.night_audit).to be_failed
    expect(result.night_audit.night_audit_logs.last.action_type).to eq("failed")
    expect(result.night_audit.night_audit_logs.last.metadata["error"]).to eq("boom")
  end
end
