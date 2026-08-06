# frozen_string_literal: true

require "rails_helper"

RSpec.describe Deposits::SyncBookingDepositStatus do
  let(:booking) { create(:booking, deposit_status: "not_required") }

  it "marks the booking pending at the hotel when a pending deposit is available" do
    create(:deposit, booking: booking, status: "pending")

    described_class.call(booking)

    expect(booking.reload.deposit_status).to eq("pending_at_hotel")
  end

  it "marks the booking held when a held deposit is available" do
    create(:deposit, booking: booking, status: "held")

    described_class.call(booking)

    expect(booking.reload.deposit_status).to eq("held")
  end

  it "marks the booking collected when a deposit has been applied" do
    deposit = create(:deposit, booking: booking)
    folio = create(:booking_folio, booking: booking, hotel: booking.hotel)
    transaction = create(:folio_transaction, booking_folio: folio)
    create(:deposit_movement, deposit: deposit, movement_type: "apply", amount: deposit.amount,
      booking_folio: folio, folio_transaction: transaction)

    described_class.call(booking)

    expect(booking.reload.deposit_status).to eq("collected")
  end

  it "marks the booking released when all deposit money has been returned" do
    deposit = create(:deposit, booking: booking, status: "released")
    create(:deposit_movement, deposit: deposit, movement_type: "release", amount: deposit.amount)

    described_class.call(booking)

    expect(booking.reload.deposit_status).to eq("released")
  end

  it "marks the booking not required when it has no security deposits" do
    described_class.call(booking)

    expect(booking.reload.deposit_status).to eq("not_required")
  end
end
