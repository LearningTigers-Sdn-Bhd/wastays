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

  def create_balanced_folio(booking, charge_amount: 200.0, payment_amount: charge_amount)
    folio = create(:booking_folio, hotel: booking.hotel, booking: booking)
    create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: charge_amount, posting_date: booking.check_in)
    create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: payment_amount, posting_date: booking.check_out)
    folio
  end

  before do
    create(:booking,
      hotel: hotel,
      status: "confirmed",
      payment_status: "captured",
      check_in: business_date,
      check_out: business_date + 1.day)
    completed_booking = create(:booking,
      hotel: hotel,
      status: "completed",
      payment_status: "pending",
      check_in: business_date - 1.day,
      check_out: business_date,
      checked_in_at: business_date.beginning_of_day,
      checked_out_at: business_date.noon)
    create_balanced_folio(completed_booking)
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

  it "posts nightly charges before completing the audit" do
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date,
      check_out: business_date + 2.days,
      checked_in_at: business_date.beginning_of_day,
      tax_lines: [ { "name" => "SST", "amount" => "20.00", "type" => "sst" } ])
    create(:booking_room, booking: booking, subtotal: 200.0)
    folio = create(:booking_folio, hotel: hotel, booking: booking)

    result = run_audit

    expect(result.success?).to be(true)
    expect(folio.folio_transactions.charge.where("metadata->>'posting_source' = ?", "night_audit").count).to eq(2)
  end

  it "blocks and logs when a due-out booking is not checked out" do
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      payment_status: "captured",
      check_in: business_date - 1.day,
      check_out: business_date,
      checked_in_at: 1.day.ago)
    create_balanced_folio(booking)

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

  it "blocks when an in-house booking has no folio" do
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date - 1.day,
      check_out: business_date + 1.day,
      checked_in_at: business_date.beginning_of_day)

    result = run_audit

    expect(result.success?).to be(false)
    expect(result.night_audit.blocked_details["missing_folio"].first["booking_id"]).to eq(booking.id)
  end

  it "blocks when an in-house booking folio is missing nightly charges" do
    allow(Folios::PostNightlyCharges).to receive(:call)
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date - 1.day,
      check_out: business_date + 1.day,
      checked_in_at: business_date.beginning_of_day)
    create(:booking_room, booking: booking, subtotal: 120.0)
    create(:booking_folio, hotel: hotel, booking: booking)

    result = run_audit

    expect(result.success?).to be(false)
    expect(result.night_audit.blocked_details["missing_nightly_charges"].first["booking_id"]).to eq(booking.id)
  end

  it "blocks when nightly charges are under-posted" do
    allow(Folios::PostNightlyCharges).to receive(:call)
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date - 1.day,
      check_out: business_date + 1.day,
      checked_in_at: business_date.beginning_of_day)
    create(:booking_room, booking: booking, subtotal: 120.0)
    folio = create(:booking_folio, hotel: hotel, booking: booking)
    create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100.0, posting_date: booking.check_in)

    result = run_audit

    expect(result.success?).to be(false)
    expect(result.night_audit.blocked_details["missing_nightly_charges"].first["booking_id"]).to eq(booking.id)
  end

  it "blocks when a due-out completed booking has an outstanding folio balance" do
    booking = create(:booking,
      hotel: hotel,
      status: "completed",
      check_in: business_date - 1.day,
      check_out: business_date,
      checked_in_at: business_date.beginning_of_day,
      checked_out_at: business_date.noon)
    folio = create(:booking_folio, hotel: hotel, booking: booking)
    create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 150.0, posting_date: booking.check_in)

    result = run_audit

    expect(result.success?).to be(false)
    expect(result.night_audit.blocked_details["outstanding_folio_balance"].first["booking_id"]).to eq(booking.id)
  end

  it "blocks when a captured payment is not synced to the booking folio" do
    booking = create(:booking,
      hotel: hotel,
      status: "completed",
      check_in: business_date - 1.day,
      check_out: business_date,
      checked_in_at: business_date.beginning_of_day,
      checked_out_at: business_date.noon)
    folio = create_balanced_folio(booking)
    payment_transaction = create(:payment_transaction, booking: booking, booking_quote: booking.booking_quote, amount_subunits: 20_000, status: "captured")

    result = run_audit

    expect(result.success?).to be(false)
    expect(result.night_audit.blocked_details["captured_payment_not_synced"].first["payment_transaction_id"]).to eq(payment_transaction.id)
    expect(folio.reload.folio_transactions.where("metadata->>'payment_transaction_id' = ?", payment_transaction.id.to_s)).to be_empty
  end

  it "blocks when a captured payment is synced with the wrong amount" do
    booking = create(:booking,
      hotel: hotel,
      status: "completed",
      check_in: business_date - 1.day,
      check_out: business_date,
      checked_in_at: business_date.beginning_of_day,
      checked_out_at: business_date.noon)
    folio = create(:booking_folio, hotel: hotel, booking: booking)
    payment_transaction = create(:payment_transaction, booking: booking, booking_quote: booking.booking_quote, amount_subunits: 20_000, status: "captured")
    create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 200.0, posting_date: booking.check_in)
    create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "gateway_payment", amount: 100.0, posting_date: booking.check_out, metadata: { payment_transaction_id: payment_transaction.id })
    create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 100.0, posting_date: booking.check_out)

    result = run_audit

    expect(result.success?).to be(false)
    expect(result.night_audit.blocked_details["captured_payment_not_synced"].first["payment_transaction_id"]).to eq(payment_transaction.id)
  end

  it "blocks when a completed refund is not synced to the booking folio" do
    booking = create(:booking,
      hotel: hotel,
      status: "completed",
      check_in: business_date - 1.day,
      check_out: business_date,
      checked_in_at: business_date.beginning_of_day,
      checked_out_at: business_date.noon)
    create_balanced_folio(booking)
    refund_request = create(:refund_request, booking: booking, status: "completed", refund_amount: 50.0)

    result = run_audit

    expect(result.success?).to be(false)
    expect(result.night_audit.blocked_details["refund_not_synced"].first["refund_request_id"]).to eq(refund_request.id)
  end

  it "blocks when a completed refund is synced with the wrong amount" do
    booking = create(:booking,
      hotel: hotel,
      status: "completed",
      check_in: business_date - 1.day,
      check_out: business_date,
      checked_in_at: business_date.beginning_of_day,
      checked_out_at: business_date.noon)
    folio = create(:booking_folio, hotel: hotel, booking: booking)
    refund_request = create(:refund_request, booking: booking, status: "completed", refund_amount: 50.0)
    create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 200.0, posting_date: booking.check_in)
    create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "gateway_payment", amount: 240.0, posting_date: booking.check_out)
    create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "refund", amount: -40.0, posting_date: booking.check_out, metadata: { refund_request_id: refund_request.id })

    result = run_audit

    expect(result.success?).to be(false)
    expect(result.night_audit.blocked_details["refund_not_synced"].first["refund_request_id"]).to eq(refund_request.id)
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
