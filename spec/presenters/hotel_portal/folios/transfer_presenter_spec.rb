# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Folios::TransferPresenter do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel:) }
  let(:folio) { create(:booking_folio, hotel:, booking:) }

  it "nests direct and legacy attached taxes and keeps the charge total exact" do
    charge = create(:folio_transaction, booking_folio: folio, amount: 2.90)
    direct = create(:folio_transaction, booking_folio: folio, category: "tax", amount: 0.17, parent_transaction: charge,
      metadata: { tax_line: { name: "SST 6%" } })
    legacy = create(:folio_transaction, booking_folio: folio, category: "tax", amount: 0.03,
      metadata: { tax_line: { source_transaction_code_id: charge.transaction_code_id }, stay_date: charge.posting_date.iso8601 })
    presenter = described_class.new(rows: [ charge, direct, legacy ])

    expect(presenter.rows_for(folio)).to eq([ charge ])
    expect(presenter.taxes(charge)).to contain_exactly(direct, legacy)
    expect(presenter.total_with_taxes(charge)).to eq(3.10.to_d)
    expect(presenter.tax_label(direct)).to eq("SST 6%")
  end

  it "nests a recorded surcharge inside its payment and keeps its taxes with the surcharge" do
    payment = create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount: 102.12,
      metadata: { payment_operation_key: "terminal:payment" })
    fee = create(:folio_transaction, booking_folio: folio, amount: 2, operation_key: "terminal:payment", metadata: { posting_source: "payment_surcharge" })
    tax = create(:folio_transaction, booking_folio: folio, category: "tax", amount: 0.12, parent_transaction: fee)
    presenter = described_class.new(rows: [ fee, tax, payment ])

    expect(presenter.rows).to eq([ payment ])
    expect(presenter.surcharges(payment)).to eq([ fee ])
    expect(presenter.taxes(fee)).to eq([ tax ])
  end

  it "recognises a configured prepayment surcharge through its application operation key" do
    payment = create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount: 50,
      metadata: { deposit_operation_key: "group-prepayment:0:#{folio.id}" })
    fee = create(:folio_transaction, booking_folio: folio, amount: 2, operation_key: "group-prepayment:surcharge", metadata: { posting_source: "payment_surcharge" })

    expect(described_class.new(rows: [ fee, payment ]).surcharges(payment)).to eq([ fee ])
  end

  it "keeps unlinked surcharges and orphan taxes visible as their own entries" do
    payment = create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount: 100)
    fee = create(:folio_transaction, booking_folio: folio, amount: 2, operation_key: "other-payment", metadata: { posting_source: "payment_surcharge" })
    tax = create(:folio_transaction, booking_folio: folio, category: "tax", amount: 0.12, metadata: { parent_transaction_id: 999999 })
    presenter = described_class.new(rows: [ fee, payment, tax ])

    expect(presenter.rows).to eq([ fee, payment, tax ])
    expect(presenter.surcharges(payment)).to be_empty
  end

  it "does not pick an arbitrary payment when a surcharge has several matching payments" do
    payments = create_list(:folio_transaction, 2, booking_folio: folio, transaction_type: "payment", category: "cash", amount: 50,
      metadata: { payment_operation_key: "original-payment" })
    fee = create(:folio_transaction, booking_folio: folio, amount: 2, operation_key: "original-payment", metadata: { posting_source: "payment_surcharge" })
    presenter = described_class.new(rows: [ *payments, fee ])

    expect(presenter.rows).to include(fee)
    payments.each { |payment| expect(presenter.surcharges(payment)).to be_empty }
  end
end
