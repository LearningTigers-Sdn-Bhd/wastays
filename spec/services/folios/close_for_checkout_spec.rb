# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::CloseForCheckout do
  let(:booking) { create(:booking, status: "checked_in", currency: "MYR") }
  let(:user) { create(:user) }

  it "closes the folio when the balance is zero" do
    folio = create(:booking_folio, booking: booking, status: "open")
    create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100.0)
    create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 100.0)

    result = described_class.call(booking: booking, user: user)

    expect(result.success?).to be(true)
    expect(result.folio).to eq(folio)
    expect(result.balance).to eq(0.to_d)
    expect(folio.reload.status).to eq("closed")
  end

  it "fails when the booking has no folio" do
    result = described_class.call(booking: booking, user: user)

    expect(result.success?).to be(false)
    expect(result.error).to eq("Booking has no folio.")
  end

  it "fails when the folio is already closed" do
    create(:booking_folio, booking: booking, status: "closed")

    result = described_class.call(booking: booking, user: user)

    expect(result.success?).to be(false)
    expect(result.error).to eq("Folio is already closed.")
  end

  it "fails with a positive outstanding balance" do
    folio = create(:booking_folio, booking: booking, status: "open")
    create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100.0)

    result = described_class.call(booking: booking, user: user)

    expect(result.success?).to be(false)
    expect(result.error).to eq("Cannot check out with outstanding balance of MYR 100.00.")
    expect(folio.reload.status).to eq("open")
  end

  it "fails with a negative credit balance" do
    folio = create(:booking_folio, booking: booking, status: "open")
    create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 50.0)

    result = described_class.call(booking: booking, user: user)

    expect(result.success?).to be(false)
    expect(result.error).to eq("Cannot check out with credit balance of MYR -50.00. Process refund or adjustment first.")
    expect(folio.reload.status).to eq("open")
  end
end
