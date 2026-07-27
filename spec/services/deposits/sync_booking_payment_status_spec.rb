# frozen_string_literal: true

require "rails_helper"

RSpec.describe Deposits::SyncBookingPaymentStatus do
  let(:booking) { create(:booking, total_amount: 100, payment_status: "pending") }
  let(:folio) { create(:booking_folio, booking: booking, hotel: booking.hotel) }

  it "keeps the booking pending when no payments have posted" do
    described_class.call(booking)

    expect(booking.reload.payment_status).to eq("pending")
  end

  it "marks the booking partial when posted payments are below its total" do
    create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "booking_payment", amount: 40)

    described_class.call(booking)

    expect(booking.reload.payment_status).to eq("partial")
  end

  it "marks the booking captured when posted payments cover its total" do
    create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "booking_payment", amount: 100)

    described_class.call(booking)

    expect(booking.reload.payment_status).to eq("captured")
  end
end
