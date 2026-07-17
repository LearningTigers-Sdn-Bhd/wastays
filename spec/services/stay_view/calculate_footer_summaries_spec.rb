# frozen_string_literal: true

require "rails_helper"

RSpec.describe StayView::CalculateFooterSummaries do
  let(:date) { Date.new(2026, 7, 16) }

  it "aggregates filtered room-type values and recalculates weighted occupancy without SQL" do
    groups = [
      room_group(1, summary(sellable: 2, sold: 1, available: 1)),
      room_group(2, summary(sellable: 8, sold: 2, available: 6))
    ]
    queries = []

    result = ActiveSupport::Notifications.subscribed(
      ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] unless payload[:cached] },
      "sql.active_record"
    ) do
      described_class.call(room_groups: groups, dates: [ date ])
    end

    expect(result.sole).to have_attributes(date:, sellable: 10, sold: 3, available: 7, occupancy: 0.3)
    expect(result.sole.occupancy).not_to eq((0.5 + 0.25) / 2)
    expect(queries).to be_empty
    expect(result).to be_frozen
    expect(result.sole).to be_frozen
  end

  it "uses only supplied visible groups and preserves their checkout and block-adjusted values" do
    visible = room_group(1, summary(sellable: 1, sold: 0, available: 1))
    filtered_out = room_group(2, summary(sellable: 4, sold: 2, available: 2))

    result = described_class.call(room_groups: [ visible ], dates: [ date ])

    expect(result.sole).to have_attributes(sellable: 1, sold: 0, available: 1, occupancy: 0.0)
    expect(result.sole.available).not_to eq(
      visible.inventory_summaries.sole.available + filtered_out.inventory_summaries.sole.available
    )
  end

  it "returns unavailable occupancy when total sellable inventory is zero" do
    result = described_class.call(
      room_groups: [ room_group(1, summary(sellable: 0, sold: 0, available: 0)) ],
      dates: [ date ]
    )

    expect(result.sole).to have_attributes(sellable: 0, sold: 0, available: 0, occupancy: nil)
  end

  private

  def room_group(id, inventory_summary)
    StayView::RoomGroup.new(room_type_id: id, name: "Type #{id}", rooms: [], inventory_summaries: [ inventory_summary ])
  end

  def summary(sellable:, sold:, available:)
    StayView::InventoryDateSummary.new(
      date:,
      sellable:,
      sold:,
      available:,
      occupancy: sellable.zero? ? nil : sold.fdiv(sellable)
    )
  end
end
