# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::CashierActivityTable do
  let(:first) { Struct.new(:id, :amount).new(1, 25.to_d) }
  let(:second) { Struct.new(:id, :amount).new(2, 40.to_d) }
  let(:report) do
    Struct.new(
      :transactions, :handling_by_transaction_id, :mode_by_transaction_id,
      :section_by_transaction_id, :received_by_key_by_transaction_id, :mode_order
    ).new(
      [ first, second ], { 1 => "gateway", 2 => "at_desk" },
      { 1 => "Online Card", 2 => "Cash" }, { 1 => "Advance", 2 => "Settlement" },
      { 1 => "gateway", 2 => "unassigned" }, [ "Cash" ]
    )
  end

  it "defaults to handling order and calculates full-group totals" do
    groups = described_class.new(report:).groups

    expect(groups.map(&:key)).to eq(%w[at_desk gateway])
    expect(groups.map(&:count)).to eq([ 1, 1 ])
    expect(groups.map(&:balance)).to eq([ 40.to_d, 25.to_d ])
  end

  it "supports payment mode and stage grouping" do
    expect(described_class.new(report:, group_by: "payment_mode").groups.map(&:key)).to eq([ "Cash", "Online Card" ])
    expect(described_class.new(report:, group_by: "stage").groups.map(&:key)).to eq(%w[Advance Settlement])
  end
end
