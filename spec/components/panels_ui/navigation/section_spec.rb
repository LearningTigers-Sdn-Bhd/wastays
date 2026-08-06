# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Navigation::Section do
  it "defaults items to an empty array" do
    section = described_class.new(label: "Operations")

    expect(section.label).to eq("Operations")
    expect(section.items).to eq([])
    expect(section.items?).to be(false)
  end

  it "reports items? when populated" do
    item = PanelsUI::Navigation::Item.new(label: "Bookings")
    section = described_class.new(label: "Operations", items: [ item ])

    expect(section.items?).to be(true)
    expect(section.items).to eq([ item ])
  end

  it "coerces an explicit nil items back to an empty array" do
    expect(described_class.new(label: "X", items: nil).items).to eq([])
  end


  it "copies and freezes the items collection" do
    items = [ PanelsUI::Navigation::Item.new(label: "Original") ]
    section = described_class.new(label: "Operations", items:)

    items << PanelsUI::Navigation::Item.new(label: "Later")

    expect(section.items.map(&:label)).to eq([ "Original" ])
    expect(section.items).to be_frozen
    expect { section.items << PanelsUI::Navigation::Item.new(label: "Blocked") }.to raise_error(FrozenError)
  end
end
