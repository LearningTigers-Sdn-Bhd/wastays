# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::UpdateStayDates do
  let(:closed_date) { Date.new(2026, 10, 6) }
  let(:open_date) { closed_date + 1.day }
  let(:hotel) { create(:hotel, time_zone: "Kuala Lumpur", accounting_business_date: open_date, sst_enabled: true) }
  let(:room_type) { create(:room_type, hotel: hotel, base_price: 108, quantity: 10) }
  let(:actor) { create(:user, account: hotel.account) }
  let(:booking) do
    create(:booking, hotel: hotel, status: "checked_in", guest_country: "Malaysia",
      check_in: hotel.hotel_time_zone.local(2026, 10, 7, 14), check_out: hotel.hotel_time_zone.local(2026, 10, 8, 12))
  end
  let!(:room) { create(:booking_room, booking: booking, room_type: room_type, rate_plan: room_type.standard_rate_plan, subtotal: 108) }
  let!(:folio) { create(:booking_folio, hotel: hotel, booking: booking) }
  let!(:audit) { create(:night_audit, hotel: hotel, business_date: closed_date, status: "completed") }
  let(:dates) { { check_in: open_date.to_s, check_out: (open_date + 1.day).to_s } }

  before do
    create(:hotel_business_date, hotel: hotel, business_date: closed_date, status: "closed")
    create(:night_audit_financial_summary, night_audit: audit, room_revenue: 0)
    code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    code.update!(is_taxable: true)
    code.transaction_code_taxes.find_or_create_by!(primary_tax_key: "sst_tax")
    allow(actor).to receive(:has_permission?).and_return(false)
    %w[manage_bookings manage_night_audit override_financial_date_lock].each do |permission|
      allow(actor).to receive(:has_permission?).with(permission, hotel: hotel).and_return(true)
    end
    Bookings::InventoryManager.new(booking).deduct
    result = Bookings::UpdateStayService.new(booking: booking, user: actor,
      params: { check_in: closed_date.to_s, check_out: open_date.to_s }).call
    raise result.errors.join unless result.success?
    allow(Notifications::Dispatcher).to receive(:new).and_call_original
  end

  it "returns a signed review without saving dates, charges, forecasts, inventory, or logs" do
    before_state = state
    result = update

    expect(result).not_to be_success
    expect(result.errors).to be_empty
    expect(result.correction_review_token).to be_present
    expect(result.correction_allowed?).to be(true)
    actions = result.correction_review.sole[:actions]
    expect(actions.map { |action| action[:action] }).to eq(%w[reverse reverse schedule schedule])
    expect(actions.select { |action| action[:action] == "reverse" }.sum { |action| action[:amount].to_d }).to eq("116.64".to_d)
    expect(state).to eq(before_state)
    expect(Notifications::Dispatcher).not_to have_received(:new)
  end

  it "reverses removed room and tax charges, retains originals, and schedules the replacement stay" do
    original_ids = folio.folio_transactions.charge.pluck(:id)
    review = update

    result = confirm(review)

    expect(result).to be_success
    expect(result.corrected?).to be(true)
    expect(booking.reload.check_in.in_time_zone(hotel.hotel_time_zone).to_date).to eq(open_date)
    expect(folio.folio_transactions.charge.pluck(:id)).to eq(original_ids)
    reversals = folio.folio_transactions.adjustment
    expect(reversals.pluck(:reversal_of_transaction_id)).to match_array(original_ids)
    expect(reversals.sum(:amount)).to eq("-116.64".to_d)
    expect(folio.folio_transactions.charge.where(voided_by_transaction_id: nil)).not_to exist
    expect(folio.folio_forecasted_charges.forecast.pluck(:stay_date).uniq).to eq([ open_date ])
    expect(audit.financial_summary.reload.adjustments_total).to eq("-116.64".to_d)
    expect(hotel.journal_batches.find_by!(business_date: closed_date).summary_data["total_transactions"]).to eq(4)
    expect(audit.night_audit_logs.order(:id).last.metadata["reason"]).to eq("Wrong arrival date")
    expect(BookingAuditLog.where(auditable: booking).order(:id).last.metadata["reason"]).to eq("Wrong arrival date")
  end

  it "requires a nonblank reason after review" do
    review = update
    before_state = state

    result = confirm(review, reason: "  ")

    expect(result.errors).to include("Reason for correction is required.")
    expect(result.correction_review).to be_present
    expect(state).to eq(before_state)
  end

  %w[manage_night_audit override_financial_date_lock].each do |permission|
    it "requires #{permission} even with a signed review and reason" do
      review = update
      allow(actor).to receive(:has_permission?).with(permission, hotel: hotel).and_return(false)
      before_state = state

      result = confirm(review)

      expect(result.errors).to include("An authorized manager must confirm this correction.")
      expect(result.correction_allowed?).to be(false)
      expect(state).to eq(before_state)
    end
  end

  it "shows the review to ordinary booking staff without permitting correction" do
    allow(actor).to receive(:has_permission?).with("manage_night_audit", hotel: hotel).and_return(false)

    result = update

    expect(result.errors).to be_empty
    expect(result.correction_review).to be_present
    expect(result.correction_allowed?).to be(false)
  end

  it "does not accept a reason without a reviewed token" do
    before_state = state

    result = update(correction_reason: "Wrong arrival date")

    expect(result).not_to be_success
    expect(result.correction_review).to be_present
    expect(state).to eq(before_state)
  end

  it "requires another review for an altered token" do
    review = update
    before_state = state

    result = update(correction_reason: "Wrong arrival date", correction_review_token: review.correction_review_token + "tampered")

    expect(result.review_message).to include("changed or expired")
    expect(state).to eq(before_state)
  end

  it "expires confirmation after fifteen minutes" do
    review = update
    before_state = state
    travel 16.minutes

    result = confirm(review)

    expect(result.review_message).to include("expired")
    expect(state).to eq(before_state)
  end

  it "requires another review if proposed dates change" do
    review = update
    before_state = state

    result = described_class.call(bookings: [ booking ], user: actor,
      params: { check_in: open_date.to_s, check_out: (open_date + 2.days).to_s },
      correction_reason: "Wrong arrival date", correction_review_token: review.correction_review_token)

    expect(result.review_message).to include("changed")
    expect(state).to eq(before_state)
  end

  it "binds the review to the actor" do
    review = update
    other_actor = create(:user, account: hotel.account)
    allow(other_actor).to receive(:has_permission?).and_return(true)
    before_state = state

    result = described_class.call(bookings: [ booking ], params: dates, user: other_actor,
      correction_reason: "Wrong arrival date", correction_review_token: review.correction_review_token)

    expect(result.review_message).to include("changed")
    expect(state).to eq(before_state)
  end

  it "requires another review when the ledger changes" do
    review = update
    original = folio.folio_transactions.charge.find_by!(category: "accommodation")
    create(:folio_transaction, booking_folio: folio, amount: 108, posting_date: closed_date,
      transaction_code: original.transaction_code,
      metadata: { reconciles_nightly_charge_key: original.metadata.fetch("nightly_charge_key") })
    before_state = state

    result = confirm(review)

    expect(result.review_message).to include("changed")
    expect(state).to eq(before_state)
  end

  it "does not duplicate reversals on a repeated confirmation" do
    review = update
    expect(confirm(review)).to be_success
    before_state = state

    expect(confirm(review)).to be_success
    expect(state).to eq(before_state)
  end

  it "posts replacements for another closed night" do
    earlier = closed_date - 1.day
    create(:hotel_business_date, hotel: hotel, business_date: earlier, status: "closed")
    create(:night_audit, hotel: hotel, business_date: earlier, status: "completed")
    proposed = { check_in: earlier.to_s, check_out: closed_date.to_s }
    review = described_class.call(bookings: [ booking ], params: proposed, user: actor)

    result = described_class.call(bookings: [ booking ], params: proposed, user: actor,
      correction_reason: "Wrong arrival date", correction_review_token: review.correction_review_token)

    expect(result).to be_success
    expect(folio.folio_transactions.charge.where(voided_by_transaction_id: nil).pluck(:posting_date).uniq).to eq([ earlier ])
    expect(folio.folio_forecasted_charges.forecast).not_to exist
    expect(hotel.journal_batches.pluck(:business_date)).to match_array([ earlier, closed_date ])
  end

  it "corrects repriced closed nights while retaining unchanged nights" do
    earlier = closed_date - 1.day
    create(:hotel_business_date, hotel: hotel, business_date: earlier, status: "closed")
    create(:night_audit, hotel: hotel, business_date: earlier, status: "completed")
    create(:room_rate, room_type: room_type, rate_plan: room.rate_plan, date: closed_date, price: 120)
    proposed = { check_in: earlier.to_s, check_out: open_date.to_s }
    review = described_class.call(bookings: [ booking ], params: proposed, user: actor)

    result = described_class.call(bookings: [ booking ], params: proposed, user: actor,
      correction_reason: "Correct stay length", correction_review_token: review.correction_review_token)

    expect(result).to be_success
    expect(folio.folio_transactions.charge.where(posting_date: closed_date, voided_by_transaction_id: nil).sum(:amount)).to eq("129.60".to_d)
    expect(folio.folio_transactions.adjustment.sum(:amount)).to eq("-116.64".to_d)
  end

  it "retains an unchanged posted night when extending into an open night" do
    original_ids = folio.folio_transactions.charge.pluck(:id)

    result = described_class.call(bookings: [ booking ], params: { check_in: closed_date.to_s, check_out: (open_date + 1.day).to_s }, user: actor)

    expect(result).to be_success
    expect(result.corrected?).to be(false)
    expect(folio.folio_transactions.pluck(:id)).to eq(original_ids)
    expect(folio.folio_forecasted_charges.forecast.pluck(:stay_date).uniq).to eq([ open_date ])
  end

  %w[posting summary journal].each do |step|
    it "rolls back the confirmed correction when #{step} fails and retains the review" do
      review = update
      before_state = state
      case step
      when "posting"
        allow_any_instance_of(Folios::Transactions::InsertTransaction).to receive(:call).and_return(Folios::Transactions::TransactionResult.failure("posting failed"))
      when "summary"
        allow_any_instance_of(NightAudits::RecalculateFinancialSummary).to receive(:call).and_raise("summary failed")
      when "journal"
        allow(Financials::CreateJournalBatch).to receive(:call).and_raise("journal failed")
      end

      result = confirm(review)

      expect(result).not_to be_success
      expect(result.errors.join).to include("#{step} failed")
      expect(result.correction_review).to be_present
      expect(state).to eq(before_state)
      expect(Notifications::Dispatcher).not_to have_received(:new)
    end
  end

  it "leaves payments and incidental charges unchanged" do
    payment = create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount: 116.64)
    incidental = create(:folio_transaction, booking_folio: folio, category: "other", amount: 15)
    review = update

    expect(confirm(review)).to be_success
    expect(payment.reload.voided_by_transaction_id).to be_nil
    expect(incidental.reload.voided_by_transaction_id).to be_nil
  end

  it "leaves a scheduled incidental charge outside the date correction" do
    incidental = create(:folio_transaction, booking_folio: folio, category: "other", amount: 15,
      posting_date: closed_date, metadata: { nightly_charge_key: "#{booking.id}:#{closed_date}:extra_charge:manual" })
    review = update

    expect(confirm(review)).to be_success
    expect(incidental.reload.voided_by_transaction_id).to be_nil
    expect(folio.folio_transactions.adjustment.sum(:amount)).to eq("-116.64".to_d)
  end

  it "rejects an unresolved accounting date even when a reason is supplied" do
    review = update
    hotel.current_business_date_record.update!(status: "audit_blocked")

    result = confirm(review)

    expect(result).not_to be_success
    expect(result.errors.join).to include("Night Audit must be resolved")
    expect(folio.folio_transactions.adjustment).not_to exist
  end

  it "blocks a missing accounting record even when a reason is supplied" do
    review = update
    hotel.hotel_business_dates.find_by!(business_date: closed_date).destroy!

    result = confirm(review)

    expect(result).not_to be_success
    expect(result.errors.join).to include("Missing accounting record")
    expect(folio.folio_transactions.adjustment).not_to exist
  end

  it "recomputes a changed price before confirmation" do
    earlier = closed_date - 1.day
    create(:hotel_business_date, hotel: hotel, business_date: earlier, status: "closed")
    create(:night_audit, hotel: hotel, business_date: earlier, status: "completed")
    proposed = { check_in: earlier.to_s, check_out: closed_date.to_s }
    review = described_class.call(bookings: [ booking ], params: proposed, user: actor)
    room_type.update!(base_price: 120)

    result = described_class.call(bookings: [ booking ], params: proposed, user: actor,
      correction_reason: "Wrong dates", correction_review_token: review.correction_review_token)

    expect(result.review_message).to include("changed")
    expect(folio.folio_transactions.adjustment).not_to exist
  end

  it "blocks closed folios before review" do
    folio.update!(status: "closed", closed_at: Time.current)

    result = update

    expect(result.errors.join).to include("Closed folios")
  end

  it "binds group confirmation to all selected bookings and rolls back a later failure" do
    second = create(:booking, hotel: hotel, status: "checked_in", guest_country: "Malaysia", check_in: booking.check_in, check_out: booking.check_out)
    create(:booking_room, booking: second, room_type: room_type, rate_plan: room.rate_plan, subtotal: 108)
    second_folio = create(:booking_folio, hotel: hotel, booking: second)
    Bookings::InventoryManager.new(second).deduct
    Bookings::PostClosedStayCharges.call(booking: second, previous_check_in: second.check_in, previous_check_out: second.check_out, user: actor)
    selected = [ booking, second ]
    review = described_class.call(bookings: selected, params: dates, user: actor)
    expect(review.correction_review.size).to eq(2)
    wrong_scope = described_class.call(bookings: [ booking ], params: dates, user: actor,
      correction_reason: "Wrong dates", correction_review_token: review.correction_review_token)
    expect(wrong_scope.review_message).to include("changed")
    calls = 0
    allow(Financials::CreateJournalBatch).to receive(:call).and_wrap_original do |original, **args|
      calls += 1
      raise "second journal failed" if calls == 2
      original.call(**args)
    end
    before_state = state
    second_ids = second_folio.folio_transactions.pluck(:id, :voided_by_transaction_id)

    result = described_class.call(bookings: selected, params: dates, user: actor,
      correction_reason: "Wrong dates", correction_review_token: review.correction_review_token)

    expect(result.errors.join).to include("second journal failed")
    expect(state).to eq(before_state)
    expect(second.reload.check_in.in_time_zone(hotel.hotel_time_zone).to_date).to eq(closed_date)
    expect(second_folio.folio_transactions.pluck(:id, :voided_by_transaction_id)).to eq(second_ids)
  end

  def update(**options)
    described_class.call(bookings: [ booking ], params: dates, user: actor, **options)
  end

  def confirm(review, reason: "Wrong arrival date")
    update(correction_reason: reason, correction_review_token: review.correction_review_token)
  end

  def state
    {
      dates: booking.reload.attributes.slice("check_in", "check_out", "total_amount"),
      transactions: folio.folio_transactions.order(:id).pluck(:id, :voided_by_transaction_id),
      forecasts: folio.folio_forecasted_charges.order(:id).pluck(:id, :status),
      inventory: room_type.room_inventories.order(:date).pluck(:date, :quantity),
      summary: audit.financial_summary.reload.attributes.except("updated_at"),
      journal: hotel.journal_batches.order(:id).map { |batch| batch.attributes.except("updated_at") },
      logs: [ BookingAuditLog.where(auditable: booking).count, audit.night_audit_logs.count, FolioOperationLog.where(booking: booking).count ]
    }
  end
end
