# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Transactions::AttachedTaxTransactions do
  let(:hotel) { create(:hotel, sst_enabled: true) }
  let(:user) { create(:user, :superadmin) }
  let(:booking) { create(:booking, hotel: hotel) }
  let(:folio) { Folios::Lifecycle::InitializeForBooking.call(booking: booking, user: user) }
  let(:room_code) { hotel.transaction_codes.find_by(system_key: "room_revenue") }

  before do
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    room_code.update!(is_taxable: true)
    room_code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")
  end

  # A late-checkout charge posts under LATE_CO but carries ROOM's tax rules. The
  # tax line records LATE_CO as its source_transaction_code_id, which is what keeps
  # this lookup — and therefore reversal, moves, and the split preview — able to
  # find the taxes belonging to that charge.
  it "finds the tax lines attached to an inherited-tax stay charge" do
    result = Folios::Charges::PostCategoryCharge.call(
      folio: folio, user: user, category: "late_checkout_charge", amount: 100.0
    )
    expect(result).to be_success

    attached = described_class.call(result.transaction)

    expect(attached.map(&:amount)).to contain_exactly(8.0)
    expect(attached.sole.id).to eq(result.tax_transactions.sole.id)
  end

  it "returns nothing for a charge that posted no taxes" do
    room_code.update!(is_taxable: false)
    result = Folios::Charges::PostCategoryCharge.call(
      folio: folio, user: user, category: "late_checkout_charge", amount: 100.0
    )

    expect(described_class.call(result.transaction)).to be_empty
  end

  it "does not claim tax lines belonging to a different charge" do
    first = Folios::Charges::PostCategoryCharge.call(
      folio: folio, user: user, category: "late_checkout_charge", amount: 100.0
    )
    second = Folios::Charges::PostCategoryCharge.call(
      folio: folio, user: user, category: "early_departure_charge", amount: 200.0
    )

    expect(described_class.call(first.transaction).map(&:id)).to eq([ first.tax_transactions.sole.id ])
    expect(described_class.call(second.transaction).map(&:id)).to eq([ second.tax_transactions.sole.id ])
  end
end
