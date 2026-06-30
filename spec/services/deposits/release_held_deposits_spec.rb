# frozen_string_literal: true

require "rails_helper"

RSpec.describe Deposits::ReleaseHeldDeposits do
  let(:booking) { create(:booking, deposit_status: "held") }
  let(:folio) { create(:booking_folio, booking: booking, hotel: booking.hotel) }
  let(:user) { create(:user) }
  let(:released_at) { Time.zone.local(2026, 6, 30, 11, 45) }

  it "releases every held deposit without creating folio transactions" do
    first_deposit = create(:deposit, booking: booking, hotel: booking.hotel, booking_folio: folio, amount: 125, metadata: { "source" => "check_in", "note" => "keep" })
    second_deposit = create(:deposit, booking: booking, hotel: booking.hotel, booking_folio: folio, amount: 75)
    released_deposit = create(:deposit, booking: booking, hotel: booking.hotel, booking_folio: folio, status: "released", amount: 20)

    expect {
      result = described_class.call(
        booking: booking,
        user: user,
        released_at: released_at,
        method: "bank_transfer",
        reference: "  BANK-42  "
      )

      expect(result.success?).to be(true)
      expect(result.deposit_ids).to contain_exactly(first_deposit.id, second_deposit.id)
      expect(result.total).to eq(200.to_d)
      expect(result.method).to eq("bank_transfer")
      expect(result.reference).to eq("BANK-42")
    }.not_to change(FolioTransaction, :count)

    expect(first_deposit.reload).to have_attributes(status: "released", released_at: released_at)
    expect(first_deposit.metadata).to include(
      "note" => "keep",
      "source" => "checkout",
      "released_by_user_id" => user.id,
      "release_method" => "bank_transfer",
      "release_reference" => "BANK-42"
    )
    expect(second_deposit.reload.status).to eq("released")
    expect(released_deposit.reload.released_at).to be_nil
    expect(booking.reload.deposit_status).to eq("released")
  end

  it "stores a blank optional reference as nil" do
    deposit = create(:deposit, booking: booking, hotel: booking.hotel, booking_folio: folio)

    result = described_class.call(booking: booking, user: user, released_at: released_at, method: "cash", reference: " ")

    expect(result.success?).to be(true)
    expect(deposit.reload.metadata["release_reference"]).to be_nil
  end

  it "rejects unsupported methods without changing deposits or booking status" do
    deposit = create(:deposit, booking: booking, hotel: booking.hotel, booking_folio: folio)

    result = described_class.call(booking: booking, user: user, released_at: released_at, method: "crypto")

    expect(result.success?).to be(false)
    expect(result.error).to eq("Security deposit release method is not supported.")
    expect(deposit.reload.status).to eq("held")
    expect(booking.reload.deposit_status).to eq("held")
  end

  it "is a successful no-op when no deposits are held" do
    create(:deposit, booking: booking, hotel: booking.hotel, booking_folio: folio, status: "forfeited")

    result = described_class.call(booking: booking, user: user, released_at: released_at, method: "manual")

    expect(result.success?).to be(true)
    expect(result.deposit_ids).to be_empty
    expect(result.total).to eq(0.to_d)
    expect(booking.reload.deposit_status).to eq("held")
  end
end
