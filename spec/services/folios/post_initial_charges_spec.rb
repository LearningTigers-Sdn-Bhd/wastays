# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::PostInitialCharges do
  let(:booking) { create(:booking, check_in: Date.current, tourism_tax_amount: 0, tax_lines: [{ "name" => "SST", "amount" => "12.00" }]) }
  let(:folio) { create(:booking_folio, booking: booking) }
  let(:user) { create(:user) }

  before do
    create(:booking_room, booking: booking, subtotal: 200.0)
  end

  it "posts accommodation and tax charges" do
    described_class.call(folio: folio, user: user)

    expect(folio.folio_transactions.charge.count).to eq(2)
    expect(folio.outstanding_balance).to eq(212.0)
  end

  it "posts legacy tourism tax when it is not present in tax lines" do
    booking.update!(tax_lines: [], tourism_tax_amount: 10.0, tourism_tax_applied: true)

    described_class.call(folio: folio, user: user)

    tax_charges = folio.folio_transactions.charge.where(category: "tax")
    expect(tax_charges.count).to eq(1)
    expect(tax_charges.first.description).to eq("Tourism Tax")
    expect(folio.outstanding_balance).to eq(210.0)
  end

  it "does not duplicate tourism tax already present in tax lines" do
    booking.update!(
      tax_lines: [{ "name" => "Tourism Tax", "amount" => "10.00" }],
      tourism_tax_amount: 10.0,
      tourism_tax_applied: true
    )

    described_class.call(folio: folio, user: user)

    tax_charges = folio.folio_transactions.charge.where(category: "tax")
    expect(tax_charges.count).to eq(1)
    expect(tax_charges.first.description).to eq("Tax: Tourism Tax")
    expect(folio.outstanding_balance).to eq(210.0)
  end

  it "detects tourism tax by tax line type" do
    booking.update!(
      tax_lines: [{ "name" => "TTx", "type" => "ttx", "amount" => "10.00" }],
      tourism_tax_amount: 10.0,
      tourism_tax_applied: true
    )

    described_class.call(folio: folio, user: user)

    tax_charges = folio.folio_transactions.charge.where(category: "tax")
    expect(tax_charges.count).to eq(1)
    expect(tax_charges.first.description).to eq("Tax: TTx")
    expect(folio.outstanding_balance).to eq(210.0)
  end

  it "raises when a transaction cannot be inserted" do
    failed_result = OpenStruct.new(success?: false, error: "posting blocked")
    insert_service = instance_double(Folios::InsertTransaction, call: failed_result)
    allow(Folios::InsertTransaction).to receive(:new).and_return(insert_service)

    expect {
      described_class.call(folio: folio, user: user)
    }.to raise_error(RuntimeError, /posting blocked/)
  end
end
