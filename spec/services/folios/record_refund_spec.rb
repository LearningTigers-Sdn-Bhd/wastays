# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::RecordRefund do
  let(:booking) { create(:booking, status: "cancelled") }
  let(:refund_request) { create(:refund_request, booking: booking, status: "approved", refund_amount: 160.0) }
  let(:user) { create(:user, :superadmin) }

  it "succeeds without posting when the booking has no folio" do
    result = described_class.call(refund_request: refund_request, user: user)

    expect(result.success?).to be true
    expect(result.transaction).to be_nil
    expect(FolioTransaction.count).to eq(0)
  end

  it "posts a negative payment transaction for a folio-backed refund" do
    folio = create(:booking_folio, booking: booking)
    create(:folio_transaction, booking_folio: folio, transaction_type: :charge, amount: 200.0)
    create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "gateway_payment", amount: 200.0)

    result = described_class.call(refund_request: refund_request, user: user)

    expect(result.success?).to be true
    transaction = result.transaction
    expect(transaction).to be_payment
    expect(transaction.category).to eq("refund")
    expect(transaction.amount).to eq(-160.0)
    expect(transaction.description).to eq("Refund completed")
    expect(transaction.metadata["refund_request_id"]).to eq(refund_request.id)
    expect(folio.outstanding_balance).to eq(160.0)
  end

  it "does not duplicate an existing refund transaction" do
    folio = create(:booking_folio, booking: booking)
    existing = create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: :payment,
      category: "refund",
      amount: -160.0,
      metadata: { refund_request_id: refund_request.id }
    )

    expect {
      result = described_class.call(refund_request: refund_request, user: user)
      expect(result.success?).to be true
      expect(result.transaction).to eq(existing)
    }.not_to change(FolioTransaction, :count)
  end

  it "returns the existing refund when insert fails after another process records it" do
    folio = create(:booking_folio, booking: booking)
    failed_result = OpenStruct.new(success?: false, error: "duplicate key")
    insert_service = instance_double(Folios::InsertTransaction, call: failed_result)
    existing = nil
    allow(insert_service).to receive(:call) do
      existing = create(
        :folio_transaction,
        booking_folio: folio,
        transaction_type: :payment,
        category: "refund",
        amount: -160.0,
        metadata: { refund_request_id: refund_request.id }
      )
      failed_result
    end
    allow(Folios::InsertTransaction).to receive(:new).and_return(insert_service)

    result = described_class.call(refund_request: refund_request, user: user)

    expect(result.success?).to be true
    expect(result.transaction).to eq(existing)
  end

  it "fails when a duplicate insert cannot load the conflicting refund" do
    create(:booking_folio, booking: booking)
    allow(Folios::InsertTransaction).to receive(:new).and_raise(ActiveRecord::RecordNotUnique)

    result = described_class.call(refund_request: refund_request, user: user)

    expect(result.success?).to be false
    expect(result.error).to eq("Refund was already recorded but could not be loaded")
  end

  it "fails when the folio transaction cannot be inserted" do
    create(:booking_folio, booking: booking)
    failed_result = OpenStruct.new(success?: false, error: "posting blocked")
    insert_service = instance_double(Folios::InsertTransaction, call: failed_result)
    allow(Folios::InsertTransaction).to receive(:new).and_return(insert_service)

    result = described_class.call(refund_request: refund_request, user: user)

    expect(result.success?).to be false
    expect(result.error).to eq("posting blocked")
  end
end
