# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightAudits::ResolveFinancialSync do
  let(:business_date) { Date.current }
  let(:hotel) { create(:hotel, :without_current_business_date) }
  let(:actor) { create(:user, :superadmin, account: hotel.account) }
  let(:booking) do
    create(
      :booking,
      hotel:,
      status: "completed",
      check_in: business_date - 1.day,
      check_out: business_date,
      checked_in_at: business_date.beginning_of_day,
      checked_out_at: business_date.noon
    )
  end
  let(:folio) { create(:booking_folio, hotel:, booking:) }
  let(:audit) { create(:night_audit, hotel:, business_date:, status: "preparing") }
  let(:payment) do
    create(
      :payment_transaction,
      booking:,
      booking_quote: booking.booking_quote,
      amount_subunits: 20_000,
      status: "captured"
    )
  end

  before do
    BusinessDates::ResetAuthority.call!(hotel:, date: business_date)
    create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 200, posting_date: business_date)
  end

  it "idempotently synchronizes a fresh payment blocker and records evidence" do
    result = described_class.call(
      night_audit: audit,
      booking:,
      actor:,
      kind: "payment",
      item_id: payment.id,
      reason: "Verified captured gateway payment"
    )

    expect(result).to be_success
    transaction = folio.folio_transactions.payment.find_by!("metadata->>'payment_transaction_id' = ?", payment.id.to_s)
    log = audit.night_audit_logs.find_by!(action_type: "blocker_resolved")
    expect(log.metadata).to include(
      "blocker_type" => "captured_payment_not_synced",
      "item_id" => payment.id,
      "folio_transaction_id" => transaction.id,
      "reason" => "Verified captured gateway payment"
    )
    expect(log.metadata.dig("before", "matching_folio_transaction_ids")).to eq([])
    expect(log.metadata.dig("after", "matching_folio_transaction_ids")).to eq([ transaction.id ])
    expect(hotel.current_business_date_record).to be_open
  end

  it "does not accept a wrong-amount ledger entry as synchronized" do
    create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: :payment,
      category: "gateway_payment",
      amount: 100,
      posting_date: business_date,
      metadata: { payment_transaction_id: payment.id }
    )

    result = described_class.call(
      night_audit: audit,
      booking:,
      actor:,
      kind: "payment",
      item_id: payment.id,
      reason: "Verify mismatch"
    )

    expect(result).not_to be_success
    expect(result.error).to eq("The payment still requires financial review.")
    expect(audit.night_audit_logs.where(action_type: "blocker_resolved")).not_to exist
  end
end
