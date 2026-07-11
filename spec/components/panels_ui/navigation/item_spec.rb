# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Navigation::Item do
  it "requires only a label; every other field defaults" do
    item = described_class.new(label: "Bookings")

    expect(item.label).to eq("Bookings")
    expect(item.path).to be_nil
    expect(item.icon).to be_nil
    expect(item.search_text).to be_nil
    expect(item.permission).to be_nil
    expect(item.permission_scope).to be_nil
    expect(item.plan_feature).to be_nil
    expect(item.active).to be(false)
    expect(item.external).to be(false)
    expect(item.children).to eq([])
  end

  it "exposes boolean predicates" do
    active_leaf = described_class.new(label: "Dashboard", active: true, external: true)
    expect(active_leaf.active?).to be(true)
    expect(active_leaf.external?).to be(true)
    expect(active_leaf.leaf?).to be(true)
    expect(active_leaf.children?).to be(false)
  end

  it "nests child Items and reports children?/leaf? accordingly" do
    child  = described_class.new(label: "Summary", path: "/reports")
    parent = described_class.new(label: "Reports", children: [ child ])

    expect(parent.children?).to be(true)
    expect(parent.leaf?).to be(false)
    expect(parent.children).to eq([ child ])
  end

  it "coerces an explicit nil children back to an empty array" do
    expect(described_class.new(label: "X", children: nil).children).to eq([])
  end

  it "is immutable" do
    item = described_class.new(label: "X")
    expect { item.instance_variable_set(:@label, "Y") }.to raise_error(FrozenError)
  end

  it "copies and freezes the children collection" do
    children = [ described_class.new(label: "Original") ]
    item = described_class.new(label: "Parent", children:)

    children << described_class.new(label: "Later")

    expect(item.children.map(&:label)).to eq([ "Original" ])
    expect(item.children).to be_frozen
    expect { item.children << described_class.new(label: "Blocked") }.to raise_error(FrozenError)
  end
end
