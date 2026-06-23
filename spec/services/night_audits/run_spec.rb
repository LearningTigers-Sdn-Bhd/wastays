require "rails_helper"

RSpec.describe NightAudits::Run do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, :without_current_business_date, account: account) }
  let(:user) { create(:user, account: account, role: "hotel_staff") }
  let(:business_date) { 2.days.ago.to_date }

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
    folio = create(:booking_folio, hotel: booking.hotel, booking: booking, folio_number: 10_000 + booking.id)
    create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: charge_amount, posting_date: booking.check_in)
    create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: payment_amount, posting_date: booking.check_out)
    folio
  end

  before do
    allow(Financials::CreateJournalBatch).to receive(:call)
    create(:booking,
      hotel: hotel,
      status: "confirmed",
      payment_status: "captured",
      check_in: business_date + 1.day,
      check_out: business_date + 2.days)
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
    expect(hotel.hotel_business_dates.find_by!(business_date: business_date)).to be_closed
    expect(hotel.hotel_business_dates.find_by!(business_date: business_date + 1.day)).to be_open

    logs = night_audit.night_audit_logs
    expect(logs.first.action_type).to eq("process_started")
    expect(logs.last.action_type).to eq("completed")

    expect(Financials::CreateJournalBatch).to have_received(:call).with(hotel: hotel, business_date: business_date)
  end

  it "records successful night audit financial audit events" do
    result = run_audit

    expect(result.success?).to be(true)
    expect(result.night_audit.financial_audit_events.pluck(:event_type)).to include(
      "night_audit_started",
      "business_date_audit_started",
      "night_audit_completed",
      "business_date_closed",
      "business_date_opened"
    )

    opened_event = result.night_audit.financial_audit_events.find_by!(event_type: "business_date_opened")
    expect(opened_event.business_date).to eq(business_date + 1.day)
    expect(opened_event.hotel_business_date.business_date).to eq(business_date + 1.day)
  end

  it "fails safely when completion audit event recording fails" do
    allow(FinancialControls::AuditEventRecorder).to receive(:call!).and_raise("audit ledger unavailable")

    result = run_audit

    expect(result.success?).to be(false)
    expect(result.night_audit).to be_failed
    expect(hotel.hotel_business_dates.find_by!(business_date: business_date)).to be_audit_blocked
    expect(hotel.hotel_business_dates.find_by(business_date: business_date + 1.day)).to be_nil
  end

  it "does not audit a date when a different accounting date is current" do
    current = create(:hotel_business_date, hotel: hotel, business_date: business_date + 1.day, status: "open")

    result = run_audit

    expect(result.success?).to be(false)
    expect(result.error).to include("is not the current accounting business date")
    expect(current.reload).to be_open
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

  it "places missed arrivals into no-show review before completing the audit" do
    booking = create(:booking,
      hotel: hotel,
      status: "confirmed",
      payment_status: "captured",
      check_in: business_date,
      check_out: business_date + 1.day)
    create(:booking_room, booking: booking, subtotal: 100.0)

    result = run_audit

    expect(result.success?).to be(true)
    expect(booking.reload.status).to eq("review_no_show")
    expect(booking.booking_folio).to be_nil
    expect(result.night_audit.summary["review_no_show_count"]).to eq(1)
  end

  it "does not keep no-shows financially relevant on later audit dates" do
    booking = create(:booking,
      hotel: hotel,
      status: "no_show",
      check_in: business_date - 1.day,
      check_out: business_date + 1.day)
    create(:booking_folio, hotel: hotel, booking: booking)

    result = run_audit

    expect(result.success?).to be(true)
    expect(result.night_audit.blocked_details["missing_folio"]).to be_empty
  end

  it "moves a missed due-out to review, records a warning, and completes without a nightly charge" do
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      payment_status: "captured",
      check_in: business_date - 1.day,
      check_out: business_date,
      checked_in_at: 1.day.ago)
    create_balanced_folio(booking)

    result = run_audit

    expect(result.success?).to be(true)
    expect(booking.reload.status).to eq("review_due_out")
    expect(result.night_audit.exceptions["review_due_out"].sole["booking_id"]).to eq(booking.id)
    expect(result.night_audit.summary.dig("run_results", "status_changes", "count")).to eq(1)
    expect(result.night_audit.summary.dig("run_results", "charges_posted", "count")).to eq(0)
    expect(result.night_audit.blocked_details["due_out_not_checked_out"]).to be_empty
  end

  it "closes with an existing review_due_out warning" do
    booking = create(:booking,
      hotel: hotel,
      status: "review_due_out",
      payment_status: "captured",
      check_in: business_date - 1.day,
      check_out: business_date,
      checked_in_at: 1.day.ago)
    create_balanced_folio(booking)

    result = run_audit

    expect(result.success?).to be(true)
    expect(result.night_audit).to be_completed
    expect(result.night_audit.exceptions["review_due_out"].sole["booking_id"]).to eq(booking.id)
  end

  it "blocks when a stale checked-in due-out fails to transition" do
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      payment_status: "captured",
      check_in: business_date - 1.day,
      check_out: business_date,
      checked_in_at: 1.day.ago)
    create_balanced_folio(booking)
    allow_any_instance_of(Bookings::TransitionStatus).to receive(:call).and_return(OpenStruct.new(success?: false, error: "transition failed"))

    result = run_audit

    expect(result.success?).to be(false)
    expect(result.night_audit).to be_blocked
    expect(booking.reload.status).to eq("checked_in")
    expect(result.night_audit.blocked_details["due_out_not_checked_out"].sole["booking_id"]).to eq(booking.id)
    expect(result.night_audit.summary.dig("run_results", "failed_items", "items").sole["reason"]).to eq("transition failed")
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

    expect(Folios::PostNightlyCharges).not_to receive(:call)

    result = run_audit

    expect(result.success?).to be(false)
    expect(result.night_audit.blocked_details["missing_folio"].first["booking_id"]).to eq(booking.id)
    expect(hotel.hotel_business_dates.find_by!(business_date: business_date)).to be_audit_blocked
  end

  it "blocks when a due-out review booking has no folio" do
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date - 1.day,
      check_out: business_date,
      checked_in_at: business_date.beginning_of_day)

    result = run_audit

    expect(result.success?).to be(false)
    expect(booking.reload.status).to eq("review_due_out")
    expect(result.night_audit.blocked_details["missing_folio"].sole["booking_id"]).to eq(booking.id)
    expect(result.night_audit.exceptions["review_due_out"].sole["booking_id"]).to eq(booking.id)
  end

  it "allows duplicate-protected nightly charge skips" do
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date,
      check_out: business_date + 1.day,
      checked_in_at: business_date.beginning_of_day)
    booking_room = create(:booking_room, booking: booking, subtotal: 120.0)
    folio = create(:booking_folio, hotel: hotel, booking: booking)
    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: :charge,
      category: "accommodation",
      amount: 120.0,
      posting_date: business_date,
      metadata: {
        posting_source: "night_audit",
        stay_date: business_date.iso8601,
        nightly_charge_key: [ booking.id, business_date.iso8601, "accommodation", booking_room.id ].join(":")
      })

    result = run_audit

    expect(result.success?).to be(true)
    expect(result.night_audit).to be_completed
    expect(result.night_audit.summary.dig("run_results", "skipped_items", "items").sole["reason"]).to eq("Nightly charge already posted")
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
    allow_any_instance_of(NightAudits::Evaluate).to receive(:call).and_raise(StandardError, "boom")

    expect { run_audit }.to change(NightAuditLog, :count).by(2) # process_started, failed

    result = run_audit

    expect(result.success?).to be(false)
    expect(result.error).to eq("boom")
    expect(result.night_audit).to be_failed
    expect(hotel.hotel_business_dates.find_by!(business_date: business_date)).to be_audit_blocked
    expect(hotel.hotel_business_dates.find_by(business_date: business_date + 1.day)).to be_nil
    expect(result.night_audit.night_audit_logs.last.action_type).to eq("failed")
    expect(result.night_audit.night_audit_logs.last.metadata["error"]).to eq("boom")
    expect(result.night_audit.summary.dig("run_results", "failed_items", "items").sole["reason"]).to eq("boom")
    expect(result.night_audit.financial_audit_events.pluck(:event_type)).to include(
      "night_audit_failed",
      "business_date_audit_blocked"
    )
  end

  it "keeps a missed arrival in review when the audit later fails" do
    booking = create(:booking, hotel: hotel, status: "confirmed", check_in: business_date, check_out: business_date + 2.days)
    create(:booking_room, booking: booking, subtotal: 200.0)
    allow_any_instance_of(NightAudits::Evaluate).to receive(:call).and_raise(StandardError, "boom")

    result = run_audit

    expect(result.success?).to be(false)
    expect(booking.reload.status).to eq("review_no_show")
    expect(booking.no_show_review_business_date).to eq(business_date)
  end

  it "blocks an expired-review charge when its posting date has no accounting control row" do
    booking = create(
      :booking,
      hotel: hotel,
      status: "review_no_show",
      no_show_review_business_date: business_date - 1.day,
      check_in: business_date - 1.day,
      check_out: business_date + 1.day,
      tax_lines: []
    )
    create(:booking_room, booking: booking, subtotal: 200.0)
    allow_any_instance_of(NightAudits::Evaluate).to receive(:call).and_raise(StandardError, "boom")

    result = run_audit

    expect(result.success?).to be(false)
    expect(result.error).to include("has no accounting control record")
    expect(booking.reload.status).to eq("review_no_show")
    expect(booking.booking_folio).to be_nil
  end

  it "does not claim a business date that is already audit_running" do
    create(:hotel_business_date, hotel: hotel, business_date: business_date, status: "audit_running")

    result = run_audit

    expect(result.success?).to be(false)
    expect(result.error).to eq("Night audit is already running for this date.")
    expect(result.night_audit).not_to be_persisted
  end

  it "marks an existing pending audit failed when the business date is not closable" do
    unclosable_date = Date.new(2026, 5, 21)
    kl_zone = Time.find_zone("Kuala Lumpur")
    existing = create(:night_audit, hotel: hotel, business_date: unclosable_date, status: "pending", trigger_mode: "manual")

    travel_to(kl_zone.local(2026, 5, 21, 10, 0)) do
      result = described_class.new(
        hotel: hotel,
        business_date: unclosable_date,
        performed_by_user: user,
        trigger_mode: "manual"
      ).call

      expect(result.success?).to be(false)
      expect(result.error).to include("cannot be audited yet")
      expect(result.night_audit.id).to eq(existing.id)
      expect(existing.reload).to be_failed
      expect(existing.completed_at).to be_present
      expect(existing.night_audit_logs.last.action_type).to eq("failed")
    end
  end

  it "allows an unclosed business date when explicitly overridden" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))

    unclosable_date = Date.new(2026, 5, 21)
    kl_zone = Time.find_zone("Kuala Lumpur")
    audit_hotel = create(:hotel, :without_current_business_date, account: account, time_zone: "Kuala Lumpur", business_starts_at: "08:00", business_ends_at: "02:00")

    travel_to(kl_zone.local(2026, 5, 21, 10, 0)) do
      result = described_class.new(
        hotel: audit_hotel,
        business_date: unclosable_date,
        performed_by_user: user,
        trigger_mode: "manual",
        allow_unclosable_date: true
      ).call

      expect(result.success?).to be(true)
      expect(result.night_audit).to be_completed
      expect(audit_hotel.hotel_business_dates.find_by!(business_date: unclosable_date)).to be_closed
    end
  end

  it "does not allow the unclosed business date override outside development" do
    unclosable_date = Date.new(2026, 5, 21)
    kl_zone = Time.find_zone("Kuala Lumpur")

    travel_to(kl_zone.local(2026, 5, 21, 10, 0)) do
      result = described_class.new(
        hotel: hotel,
        business_date: unclosable_date,
        performed_by_user: user,
        trigger_mode: "manual",
        allow_unclosable_date: true
      ).call

      expect(result.success?).to be(false)
      expect(result.error).to include("cannot be audited yet")
    end
  end

  it "does not claim a closed date when no current accounting date exists" do
    create(:hotel_business_date, hotel: hotel, business_date: business_date, status: "closed")

    result = run_audit

    expect(result.success?).to be(false)
    expect(result.error).to eq("Hotel has no current accounting business date.")
    expect(result.night_audit).not_to be_persisted
  end

  it "rejects the requested date when the next date is already current" do
    create(:hotel_business_date, hotel: hotel, business_date: business_date + 1.day, status: "audit_running")

    result = run_audit

    expect(result.success?).to be(false)
    expect(result.night_audit).not_to be_persisted
    expect(result.error).to include("is not the current accounting business date")
    expect(hotel.hotel_business_dates.find_by(business_date: business_date)).to be_nil
    expect(hotel.hotel_business_dates.find_by!(business_date: business_date + 1.day)).to be_audit_running
    expect(Financials::CreateJournalBatch).not_to have_received(:call).with(hotel: hotel, business_date: business_date)
  end
end
