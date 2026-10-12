# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::CorrectRoomCharges, frozen_time: :business_day do
  include_context "completed room-charge correction"

  it "previews the recorded taxes and folio balances without persistent changes" do
    before_state = correction_state
    hotel.update!(sst_enabled: false)
    result = review_room_correction

    expect(result.errors).to be_empty
    expect(result.review[:nights].sole).to include(current_amount: "108.0", corrected_amount: "86.4", room_amount: "80.0", difference: "-21.6")
    expect(result.review[:folios].sole).to include(current_balance: "108.0", corrected_balance: "86.4")
    expect(result.correction_review_token).to be_present
    expect(correction_state).to eq(before_state)
  end

  it "corrects original-date room and tax charges and preserves checkout and inventory" do
    originals = folio.folio_transactions.charge.to_a
    state = booking.attributes.slice("status", "check_in", "check_out", "tourism_tax_amount", "payment_status", "deposit_status")
    expect(Bookings::InventoryManager).not_to receive(:new)
    expect(Notifications::Dispatcher).not_to receive(:new)
    result = confirm_room_correction(review_room_correction)

    expect(result.errors).to be_empty
    expect(result).to be_success
    expect(booking.reload.attributes.slice(*state.keys)).to eq(state)
    expect(room.reload.subtotal).to eq(80)
    expect(booking.total_amount).to eq("86.40".to_d)
    expect(booking.manual_rate_override).to eq(80)
    expect(originals.map { |row| row.reload.voided_by_transaction_id }).to all(be_present)
    expect(folio.folio_transactions.charge.where(voided_by_transaction_id: nil).pluck(:amount)).to match_array([ 80, "6.40".to_d ])
    expect(folio.folio_transactions.pluck(:posting_date).uniq).to eq([ correction_date ])
    expect(folio.folio_forecasted_charges.forecast).not_to exist
    expect(hotel.journal_batches.find_by!(business_date: correction_date).summary_data["total_transactions"]).to eq(6)
    expect(BookingAuditLog.where(auditable: booking).last.metadata["reason"]).to eq(correction_input[:correction_reason])
  end

  it "returns success without duplicate writes for repeated confirmation" do
    review = review_room_correction
    expect(confirm_room_correction(review)).to be_success
    before_state = correction_state
    expect(confirm_room_correction(review)).to be_success
    expect(correction_state).to eq(before_state)
  end

  it "handles two submitted copies of the reviewed correction without duplicate postings" do
    review = review_room_correction
    gate = Queue.new
    workers = 2.times.map do
      Thread.new do
        gate.pop
        ActiveRecord::Base.connection_pool.with_connection do
          described_class.call(booking: Booking.find(booking.id), user: User.find(actor.id), **correction_input,
            confirm: true, correction_review_token: review.correction_review_token)
        end
      end
    end
    2.times { gate << true }
    results = workers.map(&:value)
    expect(results.map(&:errors)).to all(be_empty)
    expect(results).to all(be_success)
    expect(folio.folio_transactions.count).to eq(6)
    expect(FolioOperationLog.where(booking: booking).where("metadata->>'correction_type' = ?", "completed_room_charges").count).to eq(1)
  ensure
    workers&.each { |worker| worker.kill if worker.alive? }
  end

  it "supports a later correction without treating replacement charges as moved charges" do
    expect(confirm_room_correction(review_room_correction)).to be_success
    review = review_room_correction(nightly_amounts: amounts_for("97.20"))
    expect(review.errors).to be_empty
    result = confirm_room_correction(review, nightly_amounts: amounts_for("97.20"))
    expect(result.errors).to be_empty
    expect(result).to be_success
    expect(booking.reload.total_amount).to eq("97.20".to_d)
  end

  it "reverses removed lines when the corrected price is zero" do
    result = confirm_room_correction(review_room_correction(nightly_amounts: amounts_for("0")), nightly_amounts: amounts_for("0"))
    expect(result.errors).to be_empty
    expect(result).to be_success
    expect(folio.outstanding_balance).to eq(0)
    expect(folio.folio_transactions.charge.where(voided_by_transaction_id: nil)).not_to exist
  end

  it "requires a fresh review if the ledger changes" do
    review = review_room_correction
    create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount: 10)
    before_state = correction_state
    result = confirm_room_correction(review)
    expect(result).not_to be_success
    expect(result.review_message).to include("changed")
    expect(correction_state).to eq(before_state)
  end

  it "binds review to the amount and reason" do
    review = review_room_correction
    result = confirm_room_correction(review, correction_reason: "Different explanation")
    expect(result.review_message).to include("changed")
    expect(folio.folio_transactions.count).to eq(2)
  end

  it "binds review to the actor" do
    review = review_room_correction
    other = create(:user, account: hotel.account, role: "hotel_staff")
    create(:user_hotel_access, hotel: hotel, user: other, role: role)
    result = review_room_correction(user: other, confirm: true, correction_review_token: review.correction_review_token)
    expect(result).not_to be_success
    expect(result.review_message).to include("changed")
    expect(folio.folio_transactions.count).to eq(2)
  end

  it "blocks a changed or unresolved accounting business date" do
    review = review_room_correction
    hotel.current_business_date_record.update_column(:status, "audit_running")
    expect(confirm_room_correction(review).errors.join).to include("Night Audit")
    expect(folio.folio_transactions.count).to eq(2)
  end

  it "does not correct an unrelated discrepant incidental charge" do
    incidental = create(:folio_transaction, booking_folio: folio, amount: 30, category: "other")
    before = incidental.attributes
    expect(confirm_room_correction(review_room_correction)).to be_success
    expect(incidental.reload.attributes).to eq(before)
    expect(folio.outstanding_balance).to eq("116.40".to_d)
  end

  it "requires a fresh review for expired or altered tokens" do
    review = review_room_correction
    result = confirm_room_correction(review, correction_review_token: review.correction_review_token + "tampered")
    expect(result.review_message).to include("expired")
    travel 16.minutes
    expect(confirm_room_correction(review).review_message).to include("expired")
  end

  Bookings::CorrectRoomCharges::PERMISSIONS.each do |slug|
    it "requires #{slug} again on confirmation" do
      review = review_room_correction
      role.role_permissions.where(permission: Permission.find_by!(slug: slug)).delete_all
      expect(confirm_room_correction(review).errors.join).to include(slug)
      expect(folio.folio_transactions.count).to eq(2)
    end
  end

  it "rejects a blank correction reason" do
    expect(review_room_correction(correction_reason: "  ").errors).to include("A correction reason is required.")
  end

  it "rejects unchanged pricing" do
    expect(review_room_correction(nightly_amounts: amounts_for("108")).errors.join).to include("unchanged")
  end

  it "blocks in-house and OTA bookings" do
    booking.update_column(:status, "checked_in")
    expect(review_room_correction.errors.join).to include("checked-out")
    booking.update_columns(status: "completed", source: "ota")
    expect(review_room_correction.errors.join).to include("OTA")
  end

  it "blocks imported OTA financial snapshots on an otherwise manual booking" do
    create(:ota_financial_snapshot, booking: booking, hotel: hotel)
    expect(review_room_correction.errors.join).to include("OTA")
    expect(described_class.available?(booking: booking, user: actor)).to be(false)
  end

  it "blocks moved charge lineage" do
    original = folio.folio_transactions.charge.find_by!(category: "accommodation")
    copy = original.dup
    copy.moved_from_transaction = original
    copy.metadata = original.metadata.except("nightly_charge_key").merge("reconciles_nightly_charge_key" => original.metadata.fetch("nightly_charge_key"))
    copy.save!
    original.update!(voided_by_transaction: create(:folio_transaction, booking_folio: folio, amount: -100, transaction_type: "adjustment", category: "correction", reversal_of_transaction: original))
    expect(review_room_correction.errors.join).to include("Moved or split")
  end

  it "reopens a closed folio and leaves it open" do
    folio.update!(status: "closed", closed_at: Time.current)
    review = review_room_correction
    expect(review.review[:folios].sole[:reopen]).to be(true)
    expect(folio.reload).to be_closed
    expect(confirm_room_correction(review)).to be_success
    expect(folio.reload).to be_open
    expect(folio.closed_at).to be_nil
  end

  it "requires permission to reopen a closed folio" do
    folio.update!(status: "closed")
    role.role_permissions.where(permission: Permission.find_by!(slug: "manage_folio_windows")).delete_all
    expect(review_room_correction.errors.join).to include("reopen")
  end

  it "preserves the settled invoice revision until the corrected folio is settled and closed" do
    payment = create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount: 108)
    expect(Folios::Lifecycle::CloseFolio.call(folio: folio, user: actor)).to be_success
    original = folio.reload.invoice.current_revision
    expect(confirm_room_correction(review_room_correction)).to be_success
    expect(folio.reload.invoice).to be_under_correction
    expect(folio.invoice.current_revision).to eq(original)
    expect(payment.reload.amount).to eq(108)
    create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "refund", amount: "-21.6".to_d)
    expect(Folios::Lifecycle::CloseFolio.call(folio: folio, user: actor)).to be_success
    expect(folio.reload.invoice).to be_finalized
    expect(folio.invoice.current_revision_number).to eq(2)
    expect(folio.invoice.revisions).to include(original)
  end

  it "starts and completes the existing Direct Bill correction lifecycle" do
    relationship = create(:hotel_corporate_account, :direct_bill, hotel: hotel, credit_limit: 1_000)
    company = create(:booking_folio, :secondary, booking: booking, hotel: hotel, hotel_corporate_account: relationship)
    folio.folio_transactions.each do |row|
      row.update_column(:booking_folio_id, company.id)
      create(:folio_routing_rule, booking: booking, transaction_code: row.transaction_code, target_folio: company)
    end
    expect(Folios::Lifecycle::CloseFolio.call(folio: company, user: actor, settlement_method: "direct_bill")).to be_success
    original = company.reload.ar_invoice
    expect(confirm_room_correction(review_room_correction)).to be_success
    expect(company.reload.ar_invoice_corrections.editing).to exist
    expect(original.reload.amount).to eq(108)
    expect(original.invoice).to be_under_correction
    close = Folios::Lifecycle::CloseFolio.call(folio: company, user: actor)
    expect(close.error).to be_nil
    expect(close).to be_success
    expect(original.reload).to be_void
    expect(company.reload.ar_invoice.amount).to eq("86.40".to_d)
  end

  it "blocks unsupported legacy invoices before any reopening" do
    folio.update!(status: "closed")
    create(:invoice, booking_folio: folio, revision_snapshot: { "legacy_generated" => true })
    before_state = correction_state
    expect(review_room_correction.errors.join).to include("legacy")
    expect(correction_state).to eq(before_state)
  end

  it "limits a group correction to the selected child even when its folio is shared" do
    group = create(:group_booking, hotel: hotel)
    booking.update!(group_booking: group)
    sibling = create(:booking, :direct_hotel_payment, hotel: hotel, group_booking: group, status: "completed", total_amount: 50)
    sibling_room = create(:booking_room, booking: sibling, room_type: room_type, subtotal: 50)
    other_charge = create(:folio_transaction, booking_folio: folio, source_booking: sibling, amount: 50)
    other_values = sibling.attributes
    room_values = sibling_room.attributes
    review = review_room_correction
    expect(review.review[:folios].sole).to include(current_balance: "158.0", corrected_balance: "136.4")
    expect(confirm_room_correction(review)).to be_success
    expect(sibling.reload.attributes).to eq(other_values)
    expect(sibling_room.reload.attributes).to eq(room_values)
    expect(other_charge.reload.voided_by_transaction_id).to be_nil
  end

  it "preserves ordinary group routing to a sibling's shared folio" do
    group = create(:group_booking, hotel: hotel)
    booking.update!(group_booking: group)
    sibling = create(:booking, :direct_hotel_payment, hotel: hotel, group_booking: group, status: "completed", total_amount: 50)
    create(:booking_room, booking: sibling, room_type: room_type, subtotal: 50)
    shared = create(:booking_folio, booking: sibling, hotel: hotel)
    folio.folio_transactions.each do |row|
      row.update_column(:booking_folio_id, shared.id)
      create(:folio_routing_rule, booking: booking, transaction_code: row.transaction_code, target_folio: shared)
    end
    other_charge = create(:folio_transaction, booking_folio: shared, source_booking: sibling, amount: 50)
    result = confirm_room_correction(review_room_correction)
    expect(result.errors).to be_empty
    expect(result).to be_success
    expect(shared.outstanding_balance).to eq("136.4".to_d)
    expect(other_charge.reload.voided_by_transaction_id).to be_nil
    expect(folio.outstanding_balance).to eq(0)
  end

  %i[repair journal audit_log].each do |step|
    it "rolls back snapshots, folio reopening and ledger changes when #{step} fails" do
      folio.update!(status: "closed", closed_at: Time.current)
      review = review_room_correction
      before_state = correction_state
      case step
      when :repair
        allow(Folios::Charges::RepairNightlyChargeReconciliation).to receive(:call).and_return(OpenStruct.new(success?: false, error: "repair failed"))
      when :journal
        allow(Financials::CreateJournalBatch).to receive(:call).and_raise("journal failed")
      when :audit_log
        allow(Bookings::RecordAuditLog).to receive(:call!).and_raise("audit failed")
      end
      expect(confirm_room_correction(review)).not_to be_success
      expect(correction_state).to eq(before_state)
    end
  end

  context "same-day checkout" do
    let(:correction_date) { Date.current }

    it "corrects current open-date postings without requiring a completed audit" do
      result = confirm_room_correction(review_room_correction)
      expect(result.errors).to be_empty
      expect(result).to be_success
      expect(folio.outstanding_balance).to eq("86.40".to_d)
    end
  end

  def correction_state
    { booking: booking.reload.attributes, room: room.reload.attributes, folio: folio.reload.attributes,
      transactions: FolioTransaction.order(:id).map(&:attributes), operations: FolioOperationLog.count,
      booking_logs: BookingAuditLog.count, financial_logs: FinancialAuditEvent.count, journal_batches: JournalBatch.count }
  end
end
