# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Payments::RecordTourismTaxPayment do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel) }
  let(:user) { create(:user, :superadmin, account: hotel.account) }

  it "succeeds without posting when tourism tax was not collected" do
    create(:booking_folio, booking: booking)

    result = described_class.call(booking: booking, user: user)

    expect(result.success?).to be true
    expect(result.transaction).to be_nil
    expect(FolioTransaction.count).to eq(0)
  end

  it "fails when a collected tourism tax booking has no folio" do
    booking.update!(tourism_tax_collected: true, tourism_tax_amount: 10.0)

    result = described_class.call(booking: booking, user: user)

    expect(result.success?).to be false
    expect(result.error).to eq("Booking must have a folio before recording tourism tax payment.")
  end

  it "records a cash payment for collected tourism tax" do
    folio = create(:booking_folio, booking: booking)
    booking.update!(tourism_tax_collected: true, tourism_tax_amount: 10.0)

    result = described_class.call(booking: booking, user: user)

    expect(result.success?).to be true
    transaction = result.transaction
    expect(transaction).to be_payment
    expect(transaction.booking_folio).to eq(folio)
    expect(transaction.category).to eq("cash")
    expect(transaction.amount).to eq(10.0)
    expect(transaction.description).to eq("Tourism Tax collected at check-in")
    expect(transaction.metadata["source"]).to eq("tourism_tax_check_in")
    expect(transaction.metadata["booking_id"]).to eq(booking.id)
    expect(transaction.metadata["posted_by_user_id"]).to eq(user.id)
  end

  it "does not duplicate an existing tourism tax payment" do
    folio = create(:booking_folio, booking: booking)
    booking.update!(tourism_tax_collected: true, tourism_tax_amount: 10.0)
    existing = create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: :payment,
      category: "cash",
      amount: 10.0,
      metadata: { source: "tourism_tax_check_in" }
    )

    expect {
      result = described_class.call(booking: booking, user: user)
      expect(result.success?).to be true
      expect(result.transaction).to eq(existing)
    }.not_to change(FolioTransaction, :count)
  end
end
