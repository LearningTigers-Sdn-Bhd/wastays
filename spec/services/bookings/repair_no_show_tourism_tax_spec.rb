# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::RepairNoShowTourismTax do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, :superadmin) }
  let(:booking) { create(:booking, hotel: hotel, status: "no_show", currency: "MYR") }
  let(:folio) { create(:booking_folio, booking: booking, hotel: hotel) }

  def create_no_show_tax(type:, amount:)
    create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: :charge,
      category: "tax",
      amount: amount,
      metadata: {
        posting_source: "no_show",
        tax_line: { type: type, name: type.humanize, amount: amount.to_s }
      }
    )
  end

  it "reverses only tourism tax, links the correction, and closes the settled folio" do
    tourism_tax = create_no_show_tax(type: "tourism_tax", amount: 10)
    other_tax = create_no_show_tax(type: "sst", amount: 6)

    expect {
      @result = described_class.call(booking: booking, user: user)
    }.to change(FolioTransaction.adjustment, :count).by(1)
      .and change(FinancialAuditEvent.where(event_type: "no_show_tourism_tax_repaired"), :count).by(1)
      .and change(FinancialAuditEvent.where(event_type: "no_show_folio_closed"), :count).by(0)

    expect(@result).to be_success
    reversal = @result.reversal_transactions.sole
    expect(reversal).to have_attributes(amount: -10.to_d, category: "correction", reversal_of_transaction: tourism_tax)
    expect(tourism_tax.reload.voided_by_transaction).to eq(reversal)
    expect(other_tax.reload.voided_by_transaction).to be_nil
    expect(folio.reload).to be_open
    expect(@result.skipped_folios.sole.balance).to eq(6.to_d)
  end

  it "closes the folio when removing tourism tax produces a zero balance" do
    tourism_tax = create_no_show_tax(type: "tourism_tax", amount: 10)

    result = described_class.call(booking: booking, user: user)

    expect(result).to be_success
    expect(tourism_tax.reload).to be_reversed
    expect(folio.reload).to be_closed
    expect(result.closed_folios).to contain_exactly(folio)
  end

  it "reopens a closed folio for repair and closes it again when settled" do
    create_no_show_tax(type: "tourism_tax", amount: 10)
    folio.update!(status: "closed", closed_at: Time.current, closed_by: user)

    expect {
      @result = described_class.call(booking: booking, user: user)
    }.to change(FolioOperationLog.where(operation_type: "reopen_folio"), :count).by(1)

    expect(@result).to be_success
    expect(folio.reload).to be_closed
  end

  it "is idempotent after the tourism tax has been repaired" do
    create_no_show_tax(type: "tourism_tax", amount: 10)
    described_class.call(booking: booking, user: user)

    expect {
      @result = described_class.call(booking: booking, user: user)
    }.not_to change(FolioTransaction, :count)

    expect(@result).to be_success
    expect(@result.reversal_transactions).to be_empty
  end

  it "requires both booking-management and folio-correction permissions" do
    create_no_show_tax(type: "tourism_tax", amount: 10)

    result = described_class.call(booking: booking, user: create(:user))

    expect(result).not_to be_success
    expect(result.error).to include("permission")
    expect(folio.reload).to be_open
  end
end
