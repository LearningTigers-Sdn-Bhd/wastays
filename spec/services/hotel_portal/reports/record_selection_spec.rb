# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::RecordSelection do
  Record = Struct.new(:id, :group)

  let(:records) do
    [ Record.new(1, "direct"), Record.new(2, "direct"), Record.new(3, "walk_in") ]
  end

  def build(ids: nil, group_values: nil, excluded_ids: nil)
    described_class.new(
      records:,
      record_id: ->(record) { record.id },
      group_key: ->(record) { record.group },
      ids:, group_values:, excluded_ids:
    )
  end

  it "reports no selection when the request carries none" do
    selection = build

    expect(selection).not_to be_selected
    expect(selection.selected_ids).to be_empty
    expect(selection.selected_count).to eq(0)
  end

  it "unions single rows and whole groups, then removes the exclusions" do
    selection = build(ids: [ 3 ], group_values: [ "direct" ], excluded_ids: [ 2 ])

    expect(selection).to be_selected
    expect(selection.selected_ids).to contain_exactly(1, 3)
    expect(selection.selected_count).to eq(2)
    expect(selection).to be_record_selected(1)
    expect(selection).not_to be_record_selected(2)
  end

  it "drops ids and groups that the report does not hold" do
    selection = build(ids: [ 1, 999, "not-a-number" ], group_values: %w[direct bogus], excluded_ids: [ 888 ])

    expect(selection.ids).to contain_exactly(1)
    expect(selection.group_values).to contain_exactly("direct")
    expect(selection.excluded_ids).to be_empty
  end

  it "answers whether a group is whole or partly selected" do
    direct = records.first(2)
    selection = build(ids: [ 1 ])

    expect(selection).not_to be_group_fully_selected(direct)
    expect(selection).to be_group_partially_selected(direct)

    whole = build(group_values: [ "direct" ])
    expect(whole).to be_group_fully_selected(direct)
    expect(whole).not_to be_group_partially_selected(direct)
  end

  it "maps every selected and excluded id back to its group" do
    selection = build(ids: [ 3 ], group_values: [ "direct" ], excluded_ids: [ 2 ])

    expect(selection.id_group_keys).to eq({ "3" => "walk_in" })
    expect(selection.excluded_id_group_keys).to eq({ "2" => "direct" })
  end
end
