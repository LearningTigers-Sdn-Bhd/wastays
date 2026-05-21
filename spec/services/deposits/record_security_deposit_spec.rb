# frozen_string_literal: true

require "rails_helper"

RSpec.describe Deposits::RecordSecurityDeposit do
  it "creates a collected security deposit outside folio transactions" do
    booking = create(:booking)
    folio = create(:booking_folio, booking: booking)
    user = create(:user)

    expect {
      result = described_class.call(
        booking: booking,
        folio: folio,
        user: user,
        amount: "250.00",
        payment_method: "cash",
        external_reference: "RCPT-1"
      )

      expect(result.success?).to be(true)
      expect(result.deposit.status).to eq("collected")
      expect(result.deposit.hold_type).to eq("security")
      expect(result.deposit.gl_code).to eq("2030")
    }.to change(Deposit, :count).by(1)
      .and change(FolioTransaction, :count).by(0)
  end

  it "no-ops for blank or zero amounts" do
    booking = create(:booking)
    folio = create(:booking_folio, booking: booking)

    expect {
      result = described_class.call(booking: booking, folio: folio, user: nil, amount: "0", payment_method: "cash")
      expect(result.success?).to be(true)
      expect(result.deposit).to be_nil
    }.not_to change(Deposit, :count)
  end
end
