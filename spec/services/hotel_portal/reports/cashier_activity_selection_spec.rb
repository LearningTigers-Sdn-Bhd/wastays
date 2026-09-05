# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::CashierActivitySelection do
  Transaction = Struct.new(:id, :amount)

  it "unions explicit rows and full groups, removes exclusions, and rejects unknown IDs" do
    transactions = [ Transaction.new(1, 10), Transaction.new(2, 20), Transaction.new(3, 30) ]
    report = Struct.new(
      :transactions, :handling_by_transaction_id, :mode_by_transaction_id,
      :section_by_transaction_id, :received_by_key_by_transaction_id, :mode_order
    ).new(
      transactions, { 1 => "at_desk", 2 => "at_desk", 3 => "gateway" },
      {}, {}, {}, []
    )

    selection = described_class.new(
      report:, group_by: "handling", transaction_ids: [ 3, 999 ],
      group_values: [ "at_desk" ], excluded_transaction_ids: [ 2 ]
    )

    expect(selection).to be_selected
    expect(selection.selected_ids).to contain_exactly(1, 3)
  end
end
