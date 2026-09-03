# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Payments::GatewayOriginated do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel) }
  let(:folio) { create(:booking_folio, booking: booking, hotel: hotel) }

  def payment(**attrs)
    create(:folio_transaction, booking_folio: folio, transaction_type: "payment", **attrs)
  end

  it "is true for a payment linked to a gateway payment transaction" do
    gateway = create(:payment_transaction, booking: booking, gateway: "razorpay")
    transaction = payment(category: "gateway_payment", amount: 100, metadata: { payment_transaction_id: gateway.id })

    expect(described_class.call(transaction)).to be(true)
  end

  it "is true for a manual gateway recovery" do
    transaction = payment(category: "gateway_payment", amount: 100, metadata: { payment_source: "gateway" })

    expect(described_class.call(transaction)).to be(true)
  end

  it "is true when the posting source names the gateway" do
    transaction = payment(category: "booking_payment", amount: 100, metadata: { posting_source: "gateway_payment" })

    expect(described_class.call(transaction)).to be(true)
  end

  it "is false for a card-terminal payment that only carries the gateway_payment category" do
    card_code = hotel.transaction_codes.find_by!(system_key: "card_payment")
    transaction = payment(
      category: "gateway_payment", amount: 300, transaction_code: card_code,
      metadata: { payment_source: "card", posting_source: "staff" }
    )

    expect(described_class.call(transaction)).to be(false)
  end

  it "is false for cash taken at the front desk" do
    transaction = payment(category: "cash", amount: 100, metadata: { payment_source: "cash", posting_source: "staff" })

    expect(described_class.call(transaction)).to be(false)
  end

  it "is false for a charge, whatever its metadata says" do
    charge = create(
      :folio_transaction, booking_folio: folio, transaction_type: "charge",
      category: "accommodation", amount: 100, metadata: { posting_source: "gateway_payment" }
    )

    expect(described_class.call(charge)).to be(false)
  end
end
