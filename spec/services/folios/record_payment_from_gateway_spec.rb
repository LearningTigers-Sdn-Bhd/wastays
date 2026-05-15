# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::RecordPaymentFromGateway do
  let(:booking) { create(:booking) }
  let(:folio) { create(:booking_folio, booking: booking) }
  let(:payment_transaction) do
    create(
      :payment_transaction,
      booking: booking,
      booking_quote: booking.booking_quote,
      status: "captured",
      amount_subunits: 12_345,
      captured_at: Time.current
    )
  end

  before { folio }

  it "records a gateway payment without a user" do
    result = described_class.call(payment_transaction)

    expect(result.success?).to be true

    transaction = folio.folio_transactions.payment.last
    expect(transaction.amount).to eq(123.45)
    expect(transaction.user).to be_nil
    expect(transaction.metadata["payment_transaction_id"]).to eq(payment_transaction.id)
  end

  it "does not record the same gateway payment twice" do
    described_class.call(payment_transaction)

    expect {
      described_class.call(payment_transaction)
    }.not_to change { folio.folio_transactions.payment.count }
  end

  it "returns the existing payment when a duplicate insert loses the race" do
    existing = create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: :payment,
      category: "gateway_payment",
      amount: 123.45,
      metadata: { payment_transaction_id: payment_transaction.id }
    )

    result = described_class.call(payment_transaction)

    expect(result.success?).to be true
    expect(result.transaction).to eq(existing)
  end

  it "fails when a duplicate insert cannot load the conflicting payment" do
    allow(Folios::InsertTransaction).to receive(:new).and_raise(ActiveRecord::RecordNotUnique)

    result = described_class.call(payment_transaction)

    expect(result.success?).to be false
    expect(result.error).to eq("Gateway payment was already recorded but could not be loaded")
  end

  it "does not record uncaptured payments" do
    payment_transaction.update!(status: "pending", captured_at: nil)

    expect {
      described_class.call(payment_transaction)
    }.not_to change { folio.folio_transactions.payment.count }
  end
end
