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

  it "creates a completed night audit with payment summary only" do
    expect { run_audit }.to change(NightAudit, :count).by(1)

    night_audit = run_audit.night_audit

    expect(run_audit.success?).to be(true)
    expect(night_audit).to be_completed
    expect(night_audit.summary).to include(
      "arrivals_count" => 1,
      "due_out_count" => 1,
      "checked_out_count" => 1
    )
    expect(night_audit.summary.fetch("payment_status_counts")).to include("captured" => 1, "pending" => 1)
    expect(night_audit.blocked_details.values.flatten).to be_empty
    expect(night_audit.exceptions.values.flatten).to be_empty
  end

  it "blocks when a due-out booking is not checked out" do
    create(:booking,
      hotel: hotel,
      status: "checked_in",
      payment_status: "captured",
      check_in: business_date - 1.day,
      check_out: business_date,
      checked_in_at: 1.day.ago)

    result = run_audit

    expect(result.success?).to be(false)
    expect(result.night_audit).to be_blocked
    expect(result.night_audit.blocked_details.dig("due_out_not_checked_out").first).to include(
      "reason" => "Due out today but still not checked out"
    )
  end

  it "stores open requests as warnings only" do
    booking = hotel.bookings.first
    create(:housekeeping_request, booking: booking, status: "pending")
    create(:complaint_request, booking: booking, status: "in_progress")

    result = run_audit

    expect(result.night_audit).to be_completed
    expect(result.night_audit.summary["warning_count"]).to eq(2)
    expect(result.night_audit.exceptions.dig("open_housekeeping_requests").size).to eq(1)
    expect(result.night_audit.exceptions.dig("open_complaint_requests").size).to eq(1)
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

  it "marks the audit failed when processing raises" do
    allow_any_instance_of(described_class).to receive(:build_summary).and_raise(StandardError, "boom")

    result = run_audit

    expect(result.success?).to be(false)
    expect(result.error).to eq("boom")
    expect(result.night_audit).to be_failed
  end
end
