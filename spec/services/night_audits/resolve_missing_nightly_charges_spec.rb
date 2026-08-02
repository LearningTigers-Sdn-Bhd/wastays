# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightAudits::ResolveMissingNightlyCharges do
  let(:business_date) { Date.current }
  let(:hotel) { create(:hotel) }
  let(:actor) { create(:user, account: hotel.account) }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date,
      check_out: business_date + 1.day,
      checked_in_at: Time.current)
  end
  let!(:room) { create(:booking_room, booking: booking, subtotal: 980.0) }
  let!(:guest_folio) { create(:booking_folio, booking: booking, hotel: hotel) }
  let!(:company_folio) { create(:booking_folio, :secondary, booking: booking, hotel: hotel) }
  let(:room_code) { hotel.transaction_codes.find_by!(system_key: "room_revenue") }
  let(:sst_code) { hotel.transaction_codes.find_by!(system_key: "sst_tax") }
  let(:night_audit) do
    create(:night_audit,
      hotel: hotel,
      business_date: business_date,
      status: "blocked",
      performed_by_user: actor,
      blocked_details: { "missing_nightly_charges" => [ { "booking_id" => booking.id } ] })
  end

  before do
    allow(actor).to receive(:has_permission?).with("manage_night_audit", hotel: hotel).and_return(true)
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date)
    start_business_date_audit(hotel)
    block_business_date_audit(hotel, blockers: { "missing_nightly_charges" => [ { "booking_id" => booking.id } ] })
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: room_code, target_folio: company_folio)
    booking.update!(tax_posting_snapshot: {
      business_date.iso8601 => [
        {
          "name" => "SST 8%",
          "amount" => "78.40",
          "type" => "sst",
          "transaction_code_id" => sst_code.id,
          "source_transaction_code_id" => room_code.id,
          "source" => "transaction_code_tax_rule"
        }
      ]
    })
    create_nightly_charge(
      folio: company_folio,
      category: "accommodation",
      amount: 980.0,
      transaction_code: room_code,
      identity: room.id
    )
  end

  it "reverses a misrouted tax and reposts it to the inherited ROOM folio" do
    wrong_tax = create_nightly_charge(
      folio: guest_folio,
      category: "tax",
      amount: 78.40,
      transaction_code: sst_code,
      identity: "sst:0",
      tax_line: booking.tax_posting_snapshot[business_date.iso8601].sole
    )

    result = described_class.call(
      night_audit: night_audit,
      booking: booking,
      actor: actor,
      reason: "Company covers room and attached SST"
    )

    expect(result).to be_success
    expect(wrong_tax.reload.voided_by_transaction).to be_present
    repaired_tax = company_folio.folio_transactions.charge.where(transaction_code: sst_code).sole
    expect(repaired_tax.amount).to eq(78.40)
    expect(repaired_tax.moved_from_transaction).to eq(wrong_tax)
    expect(repaired_tax.metadata["route_source"]).to eq("follows_parent")
    expect(repaired_tax.metadata["posting_source"]).to eq("audit_blocker_resolution")
    expect(night_audit.reload.blocked_details["missing_nightly_charges"]).to be_empty
    expect(FolioOperationLog.where(operation_type: "correction", booking: booking)).to exist
    resolution_metadata = NightAuditLog.find_by!(night_audit: night_audit, action_type: "blocker_resolved").metadata
    expect(resolution_metadata.dig("before", "issues")).to be_present
    expect(resolution_metadata.dig("after", "issues")).to be_empty
    expect(FinancialAuditEvent.where(night_audit_id: night_audit.id, event_type: "audit_blocker_resolution_posted").count).to eq(2)
  end

  it "is idempotent after the booking is reconciled" do
    create_nightly_charge(
      folio: company_folio,
      category: "tax",
      amount: 78.40,
      transaction_code: sst_code,
      identity: "sst:0",
      tax_line: booking.tax_posting_snapshot[business_date.iso8601].sole
    )

    expect {
      @result = described_class.call(
        night_audit: night_audit,
        booking: booking,
        actor: actor,
        reason: "Retry repair"
      )
    }.not_to change(FolioTransaction, :count)

    expect(@result).to be_success
    expect(@result).to be_already_repaired
    expect(night_audit.reload.blocked_details["missing_nightly_charges"]).to be_empty
    expect(hotel.current_business_date_record.blockers_snapshot["missing_nightly_charges"]).to be_empty
    expect(NightAuditLog.where(night_audit: night_audit, action_type: "blocker_resolved")).not_to exist
  end

  it "rolls back the repair when resolution logging fails" do
    wrong_tax = create_nightly_charge(
      folio: guest_folio,
      category: "tax",
      amount: 78.40,
      transaction_code: sst_code,
      identity: "sst:0",
      tax_line: booking.tax_posting_snapshot[business_date.iso8601].sole
    )
    allow(NightAudits::RecordLog).to receive(:call!).and_raise("Could not record resolution log")

    expect {
      @result = described_class.call(
        night_audit: night_audit,
        booking: booking,
        actor: actor,
        reason: "Company covers room and attached SST"
      )
    }.not_to change(FolioTransaction, :count)

    expect(@result).not_to be_success
    expect(@result.error).to eq("Could not record resolution log")
    expect(wrong_tax.reload.voided_by_transaction).to be_nil
    expect(night_audit.reload.blocked_details["missing_nightly_charges"]).to contain_exactly(include("booking_id" => booking.id))
    expect(FolioOperationLog.where(operation_type: "correction", booking: booking)).not_to exist
    expect(FinancialAuditEvent.where(night_audit_id: night_audit.id, event_type: "audit_blocker_resolution_posted")).not_to exist
  end

  it "repairs an amount mismatch on the resolved folio without reusing the occupied unique key" do
    wrong_tax = create_nightly_charge(
      folio: company_folio,
      category: "tax",
      amount: 70.0,
      transaction_code: sst_code,
      identity: "sst:0",
      tax_line: booking.tax_posting_snapshot[business_date.iso8601].sole
    )

    result = described_class.call(
      night_audit: night_audit,
      booking: booking,
      actor: actor,
      reason: "Correct SST amount"
    )

    expect(result).to be_success
    expect(wrong_tax.reload.voided_by_transaction).to be_present
    repaired_tax = company_folio.folio_transactions.charge.where(transaction_code: sst_code, voided_by_transaction_id: nil).sole
    expect(repaired_tax.amount).to eq(78.40)
    expect(repaired_tax.metadata["reconciles_nightly_charge_key"]).to eq(nightly_key("tax", "sst:0"))
    expect(company_folio.folio_forecasted_charges.forecast.where(stay_date: business_date, charge_kind: "tax")).to be_none
  end

  def create_nightly_charge(folio:, category:, amount:, transaction_code:, identity:, tax_line: nil)
    metadata = {
      posting_source: "night_audit",
      night_audit_id: night_audit.id,
      stay_date: business_date.iso8601,
      charge_kind: category,
      forecast_identity: identity.to_s,
      nightly_charge_key: nightly_key(category, identity)
    }
    metadata[:tax_line] = tax_line if tax_line

    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: "charge",
      category: category,
      amount: amount,
      transaction_code: transaction_code,
      night_audit: night_audit,
      metadata: metadata)
  end

  def nightly_key(category, identity)
    Folios::Charges::ChargePostingKeys.nightly_charge_key(
      booking: booking,
      date: business_date,
      charge_kind: category,
      identity: identity
    )
  end
end
