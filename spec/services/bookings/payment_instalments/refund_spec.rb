# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::PaymentInstalments::Refund do
  include_context "with a scheduled agent booking"

  def refund(instalment, **overrides)
    described_class.call(instalment: instalment, user: staff, refund_source: "bank_transfer", reason: "Paid twice", **overrides)
  end

  before { pay(500) }

  it "posts a negative payment and marks the stage refunded, with who and why" do
    result = refund(deposit)

    expect(result).to be_success
    expect(deposit.reload).to have_attributes(status: "refunded", refunded_by_id: staff.id, refund_reason: "Paid twice")
    expect(deposit.refunded_at).to be_present
    expect(deposit.refund_folio_transaction).to have_attributes(amount: -500, category: "refund")
    expect(deposit.refund_folio_transaction.metadata).to include("refund_source" => "bank_transfer", "reason" => "Paid twice")
  end

  it "brings the booking back to unpaid without releasing it for the refunded stage" do
    refund(deposit)

    expect(booking.reload.payment_status).to eq("pending")
    expect(booking.payment_due_at).to eq(balance.due_at)
    expect(Bookings::PaymentProgress.new(booking).amount_due_now).to eq(500)
  end

  it "writes it to the audit trail" do
    refund(deposit)

    log = audit_logs("refund_completed").last
    expect(log).to have_attributes(user_id: staff.id, source: "agent_payment_panel")
    expect(log.metadata["reason"]).to eq("Paid twice")
    expect(log.new_value).to include("amount" => "500.0", "source" => "bank_transfer")
  end

  it "needs a reason and a valid source" do
    expect(refund(deposit, reason: " ").error).to eq("Say why it is being refunded.")
    expect(refund(deposit, refund_source: "coins").error).to eq("Choose where the refund is paid from.")
    expect(deposit.reload.status).to eq("paid")
  end

  it "refuses a stage that has not been paid" do
    expect(refund(balance).error).to eq("Only a stage that has been paid can be refunded.")
  end

  it "refuses to refund more than the folio holds" do
    Folios::Transactions::InsertTransaction.new(
      booking_folio: folio, amount: -300, transaction_type: "payment", category: "refund", user: staff,
      description: "desk refund", options: { system_posting: true, posting_source: "spec", metadata: { refund_source: "cash" } }
    ).call

    expect(refund(deposit.reload).error).to include("Only 200.00 is held")
    expect(deposit.reload.status).to eq("paid")
  end

  it "cannot be done twice" do
    refund(deposit)

    expect(refund(deposit).error).to eq("Only a stage that has been paid can be refunded.")
    expect(folio.folio_transactions.payment.sum(:amount)).to eq(0)
  end

  it "leaves the stage paid when the folio refuses the refund" do
    allow_any_instance_of(Folios::Transactions::InsertTransaction).to receive(:call)
      .and_return(Folios::Transactions::TransactionResult.failure("Business date is locked."))

    result = refund(deposit)

    expect(result.error).to eq("Business date is locked.")
    expect(deposit.reload.status).to eq("paid")
    expect(audit_logs("refund_completed")).to be_empty
  end
end
