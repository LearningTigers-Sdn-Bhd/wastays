# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::InitializeForBooking do
  let(:booking) { create(:booking, check_in: Date.current, tourism_tax_amount: 0, tax_lines: [{ "name" => "SST", "amount" => "12.00" }]) }
  let(:user) { create(:user) }

  before do
    create(:booking_room, booking: booking, subtotal: 200.0)
  end

  it "creates a folio with initial charges and captured payments" do
    payment_transaction = create(:payment_transaction, booking: booking, status: "captured", amount_subunits: 10_000, captured_at: Time.current)

    folio = described_class.call(booking: booking, user: user)

    expect(folio).to be_persisted
    expect(folio.booking).to eq(booking)
    expect(folio.hotel).to eq(booking.hotel)
    expect(folio.folio_transactions.charge.count).to eq(2)
    expect(folio.folio_transactions.payment.sole.metadata["payment_transaction_id"]).to eq(payment_transaction.id)
    expect(folio.outstanding_balance).to eq(112.0)
  end

  it "returns an existing folio without posting duplicate transactions" do
    existing_folio = create(:booking_folio, booking: booking)

    expect {
      result = described_class.call(booking: booking, user: user)
      expect(result).to eq(existing_folio)
    }.not_to change(FolioTransaction, :count)
  end

  it "rolls back folio creation when initial charges cannot be posted" do
    failed_result = OpenStruct.new(success?: false, error: "posting blocked")
    insert_service = instance_double(Folios::InsertTransaction, call: failed_result)
    allow(Folios::InsertTransaction).to receive(:new).and_return(insert_service)

    expect {
      described_class.call(booking: booking, user: user)
    }.to raise_error(RuntimeError, /posting blocked/)

    expect(booking.reload.booking_folio).to be_nil
  end
end
