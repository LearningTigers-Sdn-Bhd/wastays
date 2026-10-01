# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::PaymentInstalments::MarkPaid do
  include_context "with a scheduled agent booking"

  def mark(instalment, **overrides)
    described_class.call(instalment: instalment, user: staff, payment_method: "bank_transfer", reference: "TRF-77", **overrides)
  end

  it "posts the deposit to the folio and marks the stage paid" do
    result = mark(deposit)

    expect(result).to be_success
    expect(deposit.reload).to have_attributes(status: "paid", paid_by_id: staff.id)
    expect(deposit.payment_folio_transaction).to have_attributes(amount: 500, category: "booking_payment")
    expect(deposit.payment_folio_transaction.metadata).to include("reference" => "TRF-77", "payment_method" => "bank_transfer")
    expect(deposit.note).to include("bank transfer", "TRF-77")
    expect(booking.reload).to have_attributes(payment_status: "partial", payment_due_at: balance.due_at)
  end

  it "records who did it in the audit trail" do
    mark(deposit, note: "Paid at the desk")

    log = audit_logs("payment_recorded").last
    expect(log).to have_attributes(user_id: staff.id, source: "agent_payment_panel", category: "financial")
    expect(log.new_value).to include("amount" => "500.0", "reference" => "TRF-77")
    expect(log.metadata["reason"]).to eq("Paid at the desk")
  end

  it "marks the balance paid once the deposit is, and clears the deadline" do
    mark(deposit)
    mark(balance)

    expect(booking.reload.payment_instalments.map(&:status)).to eq(%w[paid paid])
    expect(booking.payment_status).to eq("captured")
    expect(booking.payment_due_at).to be_nil
  end

  it "refuses the balance while the deposit is still owed" do
    result = mark(balance)

    expect(result).not_to be_success
    expect(result.error).to eq("Record the earlier stage first.")
    expect(folio.folio_transactions.count).to eq(0)
  end

  it "posts only what is still owed when part of the deposit is already on the folio" do
    pay(200)

    mark(deposit)

    expect(deposit.reload.payment_folio_transaction.amount).to eq(300)
    expect(booking.reload.payment_instalments.map(&:status)).to eq(%w[paid pending])
  end

  it "settles a stage the folio already covers without posting again" do
    pay(500)
    deposit.update_columns(status: "pending", paid_at: nil)

    expect { mark(deposit) }.not_to change { folio.folio_transactions.count }
    expect(deposit.reload.status).to eq("paid")
  end

  it "asks for a reference and a payment method" do
    expect(mark(deposit, reference: " ").error).to eq("Enter the reference (receipt or transfer number).")
    expect(mark(deposit, payment_method: "barter").error).to eq("Choose how it was paid.")
    expect(deposit.reload.status).to eq("pending")
  end

  it "refuses a stage that is not owed" do
    mark(deposit)

    result = mark(deposit)

    expect(result.error).to eq("Only a stage still owed can be marked paid.")
    expect(folio.folio_transactions.count).to eq(1)
  end

  it "refuses on a cancelled booking" do
    booking.update_columns(status: "cancelled")

    expect(mark(deposit).error).to eq("This booking is cancelled, so nothing more is owed on it.")
  end

  it "leaves nothing half done when the folio refuses the posting" do
    allow_any_instance_of(Folios::Transactions::InsertTransaction).to receive(:call)
      .and_return(Folios::Transactions::TransactionResult.failure("Folio is closed."))

    result = mark(deposit)

    expect(result.error).to eq("Folio is closed.")
    expect(deposit.reload.status).to eq("pending")
    expect(audit_logs("payment_recorded")).to be_empty
  end

  it "posts to a folio that has already closed" do
    folio.update_columns(status: "closed")

    expect(mark(deposit)).to be_success
  end
end
