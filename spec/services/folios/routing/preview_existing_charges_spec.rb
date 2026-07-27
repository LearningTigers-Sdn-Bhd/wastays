# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Routing::PreviewExistingCharges do
  it "returns eligible existing charges in posting order with totals" do
    booking = create(:booking)
    hotel = booking.hotel
    source_folio = create(:booking_folio, booking:, hotel:)
    target_folio = create(:booking_folio, :secondary, booking:, hotel:)
    code = create(:transaction_code, hotel:)
    other_code = create(:transaction_code, hotel:)
    rule = create(:folio_routing_rule, booking:, hotel:, transaction_code: code, target_folio: target_folio,
      effective_from: Date.new(2026, 7, 2), effective_until: Date.new(2026, 7, 5))
    later = create(:folio_transaction, booking_folio: source_folio, transaction_code: code,
      posting_date: Date.new(2026, 7, 4), amount: 80)
    earlier = create(:folio_transaction, booking_folio: source_folio, transaction_code: code,
      posting_date: Date.new(2026, 7, 2), amount: 20)
    create(:folio_transaction, booking_folio: source_folio, transaction_code: code,
      posting_date: Date.new(2026, 7, 1), amount: 10)
    create(:folio_transaction, booking_folio: source_folio, transaction_code: code,
      posting_date: Date.new(2026, 7, 6), amount: 10)
    create(:folio_transaction, booking_folio: target_folio, transaction_code: code,
      posting_date: Date.new(2026, 7, 3), amount: 10)
    create(:folio_transaction, booking_folio: source_folio, transaction_code: other_code,
      posting_date: Date.new(2026, 7, 3), amount: 10)
    create(:folio_transaction, booking_folio: source_folio, transaction_code: code,
      transaction_type: "payment", category: "cash", posting_date: Date.new(2026, 7, 3), amount: 10)

    result = described_class.call(rule: rule)

    expect(result.transactions).to eq([ earlier, later ])
    expect(result.count).to eq(2)
    expect(result.amount).to eq(100.to_d)
  end

  it "excludes voided and reversal transactions and applies the through date" do
    booking = create(:booking)
    hotel = booking.hotel
    source_folio = create(:booking_folio, booking:, hotel:)
    target_folio = create(:booking_folio, :secondary, booking:, hotel:)
    code = create(:transaction_code, hotel:)
    rule = create(:folio_routing_rule, booking:, hotel:, transaction_code: code, target_folio: target_folio)
    included = create(:folio_transaction, booking_folio: source_folio, transaction_code: code,
      posting_date: Date.new(2026, 7, 2), amount: 25)
    voided = create(:folio_transaction, booking_folio: source_folio, transaction_code: code,
      posting_date: Date.new(2026, 7, 2), amount: 30)
    reversal = create(:folio_transaction, booking_folio: source_folio, transaction_code: code,
      posting_date: Date.new(2026, 7, 2), amount: 35)
    after_through = create(:folio_transaction, booking_folio: source_folio, transaction_code: code,
      posting_date: Date.new(2026, 7, 3), amount: 40)
    voided.update_column(:voided_by_transaction_id, after_through.id)
    reversal.update_column(:reversal_of_transaction_id, included.id)

    result = described_class.call(rule: rule, through: Date.new(2026, 7, 2))

    expect(result.transactions).to eq([ included ])
    expect(result.count).to eq(1)
    expect(result.amount).to eq(25.to_d)
  end
end
