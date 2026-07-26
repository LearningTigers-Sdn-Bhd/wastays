# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Routing::ApplyExistingCharges do
  it "rejects unsupported confirmation choices" do
    rule = create(:folio_routing_rule)

    result = described_class.call(rule: rule, actor: nil, reason: "Route charges", confirmation: "all")

    expect(result).not_to be_success
    expect(result.error).to eq("Choose existing_and_future or future_only.")
    expect(result.transactions).to eq([])
  end

  it "does not move transactions when confirmation is future only" do
    rule = create(:folio_routing_rule)
    allow(Folios::Transactions::MoveTransaction).to receive(:call)

    result = described_class.call(rule: rule, actor: nil, reason: "Future only", confirmation: "future_only")

    expect(result).to be_success
    expect(result.transactions).to eq([])
    expect(Folios::Transactions::MoveTransaction).not_to have_received(:call)
  end

  it "moves eligible existing charges to the rule target folio" do
    booking = create(:booking)
    hotel = booking.hotel
    source_folio = create(:booking_folio, booking: booking, hotel: hotel)
    target_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel)
    code = create(:transaction_code, hotel: hotel)
    rule = create(:folio_routing_rule, booking: booking, hotel: hotel, transaction_code: code, target_folio: target_folio)
    actor = create(:user, account: hotel.account)
    charge = create(:folio_transaction, booking_folio: source_folio, transaction_code: code, amount: 75)
    moved = create(:folio_transaction, booking_folio: target_folio, transaction_code: code, amount: 75)
    allow(Folios::Transactions::AttachedTaxTransactions).to receive(:call).with(charge).and_return([])
    allow(Folios::Transactions::MoveTransaction).to receive(:call).and_return(Folios::Transactions::MoveResult.success(transactions: [ moved ], transaction: moved))

    result = described_class.call(rule: rule, actor: actor, reason: "Move historical charge", confirmation: "existing_and_future")

    expect(result).to be_success
    expect(result.transactions).to eq([ moved ])
    expect(Folios::Transactions::MoveTransaction).to have_received(:call).with(
      transaction: charge,
      target_folio: target_folio,
      user: actor,
      reason: "Move historical charge",
      tax_routes: {}
    )
  end

  it "short-circuits when a move fails and keeps already moved transactions" do
    booking = create(:booking)
    hotel = booking.hotel
    source_folio = create(:booking_folio, booking: booking, hotel: hotel)
    target_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel)
    code = create(:transaction_code, hotel: hotel)
    rule = create(:folio_routing_rule, booking: booking, hotel: hotel, transaction_code: code, target_folio: target_folio)
    first = create(:folio_transaction, booking_folio: source_folio, transaction_code: code, posting_date: Date.new(2026, 7, 1), amount: 50)
    second = create(:folio_transaction, booking_folio: source_folio, transaction_code: code, posting_date: Date.new(2026, 7, 2), amount: 60)
    moved = create(:folio_transaction, booking_folio: target_folio, transaction_code: code, amount: 50)
    allow(Folios::Transactions::AttachedTaxTransactions).to receive(:call).with(first).and_return([])
    allow(Folios::Transactions::AttachedTaxTransactions).to receive(:call).with(second).and_return([])
    allow(Folios::Transactions::MoveTransaction).to receive(:call)
      .and_return(Folios::Transactions::MoveResult.success(transactions: [ moved ], transaction: moved), Folios::Transactions::MoveResult.failure("Move failed", transactions: []))

    result = described_class.call(rule: rule, actor: nil, reason: "Move", confirmation: "existing_and_future")

    expect(result).not_to be_success
    expect(result.error).to eq("Move failed")
    expect(result.transactions).to eq([ moved ])
    expect(Folios::Transactions::MoveTransaction).to have_received(:call).twice
  end
end
