# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::NavigationHelper, type: :helper do
  let(:hotel) { instance_double(Hotel, name: "Descendant Inn") }

  it "builds breadcrumbs for a two-level active navigation group" do
    leaf = described_class::NavItem.new(label: "Summary", path: "/reports", active: true)
    task_group = described_class::NavItem.new(label: "Reports", path: "/reports", active: false, children: [ leaf ])
    section = described_class::NavSection.new(label: "", items: [ task_group ])

    allow(helper).to receive(:hotel_sidebar_sections).and_return([ section ])

    # The trail starts at the active section: the sidebar header already says
    # which portal this is, so a "Hotel Portal" root only ate horizontal space.
    # An unlabelled section contributes nothing, so the group supplies the first
    # crumb exactly as it always did.
    expect(helper.hotel_breadcrumb_parts).to eq([
      { type: :section, label: "Reports" },
      { type: :menu, label: "Summary", path: "/reports", siblings: [ { label: "Summary", path: "/reports" } ] }
    ])
  end

  it "takes the first crumb from the section label when a layer is flat" do
    active = described_class::NavItem.new(label: "Invoices", path: "/invoices", active: true)
    sibling = described_class::NavItem.new(label: "Statements", path: "/statements")
    section = described_class::NavSection.new(label: "Cashiering", items: [ active, sibling ])

    allow(helper).to receive(:hotel_sidebar_sections).and_return([ section ])

    # Nothing wraps the page any more, so without the section label the trail
    # would collapse to the page name alone.
    expect(helper.hotel_breadcrumb_parts).to eq([
      { type: :section, label: "Cashiering" },
      { type: :menu, label: "Invoices", path: "/invoices", siblings: [
        { label: "Invoices", path: "/invoices" },
        { label: "Statements", path: "/statements" }
      ] }
    ])
  end

  it "nests a group under its section label when both are present" do
    leaf = described_class::NavItem.new(label: "Refund Report", path: "/refunds", active: true)
    group = described_class::NavItem.new(label: "Financial", children: [ leaf ])
    section = described_class::NavSection.new(label: "Reports", items: [ group ])

    allow(helper).to receive(:hotel_sidebar_sections).and_return([ section ])

    expect(helper.hotel_breadcrumb_parts).to eq([
      { type: :section, label: "Reports" },
      { type: :menu_group, label: "Financial" },
      { type: :menu, label: "Refund Report", path: "/refunds", siblings: [ { label: "Refund Report", path: "/refunds" } ] }
    ])
  end

  describe "#hotel_visible_sidebar_sections" do
    let(:item_class) { PanelsUI::Navigation::Item }
    let(:section_class) { PanelsUI::Navigation::Section }

    it "recursively filters denied items and removes empty groups and sections" do
      allowed_child = item_class.new(label: "Allowed child", path: "/allowed", permission: "allowed")
      denied_child = item_class.new(label: "Denied child", path: "/denied", permission: "denied")
      allowed_group = item_class.new(label: "Mixed group", children: [ allowed_child, denied_child ])
      empty_group = item_class.new(label: "Empty group", children: [ denied_child ])
      denied_leaf = item_class.new(label: "Denied leaf", path: "/denied-leaf", permission: "denied")
      sections = [
        section_class.new(label: "Visible", items: [ allowed_group, empty_group ]),
        section_class.new(label: "Empty", items: [ denied_leaf ])
      ]

      allow(helper).to receive(:hotel_sidebar_sections).and_return(sections)
      allow(helper).to receive(:hotel_user_has_permission?) { |permission| permission != "denied" }
      allow(helper).to receive(:feature_enabled_for_nav_item?).and_return(true)

      projected = helper.hotel_visible_sidebar_sections

      expect(projected.map(&:label)).to eq([ "Visible" ])
      expect(projected.first).to be_a(PanelsUI::Navigation::Section)
      expect(projected.first.items.map(&:label)).to eq([ "Mixed group" ])
      expect(projected.first.items.first.children.map(&:label)).to eq([ "Allowed child" ])
      expect(projected.first.items.first.children.first).to be_a(PanelsUI::Navigation::Item)
    end

    it "applies plan feature filtering to parents and children" do
      enabled = item_class.new(label: "Enabled", path: "/enabled", plan_feature: "enabled")
      disabled = item_class.new(label: "Disabled", path: "/disabled", plan_feature: "disabled")
      group = item_class.new(label: "Features", children: [ enabled, disabled ])

      allow(helper).to receive(:hotel_sidebar_sections).and_return([
        section_class.new(label: "Plans", items: [ group, disabled ])
      ])
      allow(helper).to receive(:hotel_user_has_permission?).and_return(true)
      allow(helper).to receive(:feature_enabled_for_nav_item?) { |item| item.plan_feature != "disabled" }

      projected = helper.hotel_visible_sidebar_sections

      expect(projected.first.items.map(&:label)).to eq([ "Features" ])
      expect(projected.first.items.first.children.map(&:label)).to eq([ "Enabled" ])
    end
  end
end
