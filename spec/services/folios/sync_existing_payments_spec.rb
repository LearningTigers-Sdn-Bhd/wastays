# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::SyncExistingPayments do
  let(:booking) { create(:booking) }
  let(:folio) { create(:booking_folio, booking: booking) }
  let(:user) { create(:user) }

  it "posts captured gateway payments as system transactions" do
    payment_transaction = create(:payment_transaction, booking: booking, status: "captured", amount_subunits: 10_000, captured_at: Time.current)

    described_class.call(folio: folio, user: user)

    transaction = folio.folio_transactions.payment.sole
    expect(transaction.amount).to eq(100.0)
    expect(transaction.user).to be_nil
    expect(transaction.metadata["payment_transaction_id"]).to eq(payment_transaction.id)
  end

  it "skips non-captured payment transactions" do
    create(:payment_transaction, booking: booking, status: "pending", amount_subunits: 10_000, captured_at: nil)

    expect {
      described_class.call(folio: folio, user: user)
    }.not_to change { folio.folio_transactions.payment.count }
  end

  it "does not post the same payment twice" do
    create(:payment_transaction, booking: booking, status: "captured", amount_subunits: 10_000, captured_at: Time.current)

    described_class.call(folio: folio, user: user)

    expect {
      described_class.call(folio: folio, user: user)
    }.not_to change { folio.folio_transactions.payment.count }
  end

  it "raises when a payment transaction cannot be inserted" do
    create(:payment_transaction, booking: booking, status: "captured", amount_subunits: 10_000, captured_at: Time.current)
    failed_result = OpenStruct.new(success?: false, error: "posting blocked")
    insert_service = instance_double(Folios::InsertTransaction, call: failed_result)
    allow(Folios::InsertTransaction).to receive(:new).and_return(insert_service)

    expect {
      described_class.call(folio: folio, user: user)
    }.to raise_error(RuntimeError, /posting blocked/)
  end
end
