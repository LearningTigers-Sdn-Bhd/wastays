# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Direct Bill folio correction" do
  let(:booking) { create(:booking, status: "completed", currency: "MYR") }
  let(:user) { create(:user, :superadmin) }
  let(:account) { create(:hotel_corporate_account, :direct_bill, hotel: booking.hotel) }
  let(:folio) { create(:booking_folio, :secondary, booking: booking, hotel: booking.hotel, hotel_corporate_account: account, status: "open") }
  let!(:charge) { create(:folio_transaction, booking_folio: folio, amount: 2000) }

  def close(**options)
    Folios::Lifecycle::CloseFolio.call(folio: folio.reload, user: user, settlement_method: "direct_bill", **options)
  end

  def reopen
    Folios::Lifecycle::ReopenFolio.call(folio: folio.reload, user: user, reason: "Wrong charge")
  end

  def pay(amount)
    result = ArPayments::RecordPayment.call(hotel: booking.hotel, hotel_corporate_account: account,
      user: user, amount: amount, currency: "MYR", reference_number: "BANK-1", received_at: Date.current,
      payment_method: "bank_transfer", allocations: { folio.ar_invoice.id => amount })
    expect(result).to be_success
    result.ar_payment
  end

  before { expect(close).to be_success }

  it "requires a reason and leaves the posted invoice unchanged on rejection" do
    result = Folios::Lifecycle::ReopenFolio.call(folio: folio.reload, user: user)
    expect(result.error).to include("Reason is required")
    expect(folio.reload).to be_closed
    expect(folio.ar_invoice.invoice).to be_finalized
    expect(ArInvoiceCorrection.count).to eq(0)
  end

  it "preserves the original amount while editing and replaces it when closed" do
    original = folio.reload.ar_invoice
    snapshot = original.invoice.current_revision.snapshot
    expect(reopen).to be_success
    expect(original.reload.amount).to eq(2000)
    expect(original.invoice.reload).to be_under_correction
    create(:folio_transaction, :adjustment, category: "correction", booking_folio: folio, amount: -200)
    expect(close).to be_success
    replacement = folio.reload.ar_invoice
    expect(original.reload).to be_void
    expect(original.amount).to eq(2000)
    expect(original.invoice.current_revision.snapshot).to eq(snapshot)
    expect(replacement.amount).to eq(1800)
    expect(replacement.outstanding_amount).to eq(1800)
    expect(replacement.due_on).to eq(original.due_on)
    expect(ArInvoiceCorrection.last.credit_reference).to eq("#{original.formatted_invoice_number}-CN")
  end

  it "carries a full payment and keeps the excess as unapplied company credit" do
    payment = pay(2000)
    receipt = payment.receipt
    original = folio.ar_invoice
    expect(reopen).to be_success
    create(:folio_transaction, :adjustment, category: "correction", booking_folio: folio, amount: -200)
    expect(close).to be_success
    expect(folio.reload.ar_invoice).to be_paid
    expect(folio.ar_invoice.paid_amount).to eq(1800)
    expect(payment.reload.unallocated_amount).to eq(200)
    expect(payment.receipt).to eq(receipt)
    expect(original.reload.paid_amount).to eq(0)
    expect(original.ar_payment_allocations.first).to be_reversed
  end

  it "carries a partial payment and leaves only the corrected remainder due" do
    payment = pay(1000)
    expect(reopen).to be_success
    create(:folio_transaction, booking_folio: folio, amount: 300)
    expect(close).to be_success
    expect(folio.reload.ar_invoice.paid_amount).to eq(1000)
    expect(folio.ar_invoice.outstanding_amount).to eq(1300)
    expect(payment.reload.unallocated_amount).to eq(0)
  end

  it "closes without replacement when nothing changed" do
    original = folio.ar_invoice
    expect(reopen).to be_success
    expect { expect(close).to be_success }.not_to change(ArInvoice, :count)
    expect(folio.reload.ar_invoice).to eq(original)
    expect(original.invoice.reload).to be_finalized
    expect(ArInvoiceCorrection.last).to be_unchanged
  end

  it "cancels a zero balance and restores all allocated money" do
    payment = pay(2000)
    expect(reopen).to be_success
    create(:folio_transaction, :adjustment, category: "correction", booking_folio: folio, amount: -2000)
    expect(close).to be_success
    expect(folio.reload.ar_invoice).to be_nil
    expect(payment.reload.unallocated_amount).to eq(2000)
  end

  it "rejects a negative corrected balance without changing the original" do
    original = folio.ar_invoice
    expect(reopen).to be_success
    create(:folio_transaction, :adjustment, category: "correction", booking_folio: folio, amount: -2100)
    expect(close.error).to include("negative")
    expect(folio.reload).to be_open
    expect(original.reload).not_to be_void
  end

  it "locks the company and currency" do
    expect(reopen).to be_success
    expect(folio.update(currency: "USD")).to be(false)
    expect(folio.errors[:currency]).to include("cannot change after a Direct Bill invoice is issued")
  end

  it "blocks new allocations but permits recording unapplied money" do
    original = folio.ar_invoice
    expect(reopen).to be_success
    payment = create(:ar_payment, hotel: booking.hotel, hotel_corporate_account: account, amount: 100)
    result = ArPayments::AllocatePayment.call(payment: payment, user: user, allocations: { original.id => 100 })
    expect(result).not_to be_success
    expect(payment.reload.unallocated_amount).to eq(100)
  end

  it "rolls back document cancellation and allocation reversals if replacement fails" do
    payment = pay(1000)
    original = folio.ar_invoice
    expect(reopen).to be_success
    create(:folio_transaction, booking_folio: folio, amount: 100)
    allow(Folios::Lifecycle::CreateDirectBillArInvoice).to receive(:call!).and_raise("Replacement failed")
    expect(close).not_to be_success
    expect(folio.reload).to be_open
    expect(original.reload).not_to be_void
    expect(original.paid_amount).to eq(1000)
    expect(payment.reload.allocated_amount).to eq(1000)
    expect(original.ar_payment_allocations.first).not_to be_reversed
  end
  it "supports successive corrections and does not create duplicates on a repeated close" do
    expect(reopen).to be_success
    create(:folio_transaction, booking_folio: folio, amount: 100)
    expect(close).to be_success
    correction = ArInvoiceCorrection.last
    ArInvoices::ProcessCorrectionJob.perform_now(correction.id)
    expect(correction.reload).to be_completed
    expect { expect(close).not_to be_success }.not_to change(ArInvoice, :count)
    expect(reopen).to be_success
    create(:folio_transaction, booking_folio: folio, amount: 200)
    expect(close).to be_success
    expect(folio.reload.ar_invoice.amount).to eq(2300)
    expect(folio.receivable_history.count).to eq(3)
    expect(folio.receivable_history.where.not(status: "void").count).to eq(1)
  end

  it "keeps a gateway receipt unapplied while its suggested invoice is under correction" do
    original = folio.ar_invoice
    expect(reopen).to be_success
    intent = create(:corporate_ar_payment_intent, hotel: booking.hotel, hotel_corporate_account: account,
      amount: 100, currency: "MYR", gateway_order_id: "correction-order",
      remittance_suggestions: [ { ar_invoice_id: original.id, suggested_amount: "100" } ])
    result = CorporateArPayments::CaptureIntent.call(intent: intent, gateway: "razorpay", event_source: "spec",
      verification_result: { status: "captured", external_reference: "correction-payment",
        gateway_order_id: "correction-order", amount: 10000, currency: "MYR", payment_method: "card" })
    expect(result).to be_success
    expect(result.ar_payment.unallocated_amount).to eq(100)
    expect(result.ar_payment.receipt).to be_present
    expect(original.reload.paid_amount).to eq(0)
  end

  it "enforces one current invoice at the database boundary" do
    duplicate = folio.ar_invoice.invoice.dup
    duplicate.invoice_number = 999999
    duplicate.invoice_reference = "duplicate-current"
    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "prevents overriding a closed AR folio or posting folio payments during correction" do
    result = Folios::Transactions::InsertTransaction.new(booking_folio: folio, amount: 100,
      transaction_type: "charge", category: "other", user: user, description: "Extra",
      options: { override_closed_folio: true, correction_reason: "Fix", correction_note: "Fix charge" }).call
    expect(result.error).to include("Reopen")
    expect(reopen).to be_success
    result = Folios::Transactions::InsertTransaction.new(booking_folio: folio, amount: 100,
      transaction_type: "payment", category: "cash", user: user, description: "Payment").call
    expect(result.error).to include("Accounts Receivable")
  end
end
