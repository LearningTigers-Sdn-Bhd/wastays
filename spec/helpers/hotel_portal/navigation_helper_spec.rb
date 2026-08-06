# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::NavigationHelper, type: :helper do
  let(:hotel) { instance_double(Hotel, name: "Descendant Inn") }
  let(:user) { instance_double(User, superadmin?: false) }

  describe "#hotel_sidebar_footer_items" do
    before do
      current_user = user
      helper.define_singleton_method(:current_user) { current_user }
    end

    it "has no footer items for regular hotel users" do
      expect(helper.hotel_sidebar_footer_items).to eq([])
    end

    it "adds the external admin portal destination for superadmins" do
      allow(user).to receive(:superadmin?).and_return(true)

      items = helper.hotel_sidebar_footer_items

      expect(items.map(&:label)).to eq([ "Go to Admin Portal" ])
      expect(items.last).to be_external
    end
  end

  it "builds breadcrumbs for a two-level active navigation group" do
    leaf = described_class::NavItem.new(label: "Summary", path: "/reports", active: true)
    task_group = described_class::NavItem.new(label: "Reports", path: "/reports", active: false, children: [ leaf ])
    section = described_class::NavSection.new(label: "Navigation", items: [ task_group ])

    allow(helper).to receive(:hotel_sidebar_sections).and_return([ section ])

    # The trail starts at the active section: the sidebar header already says
    # which portal this is, so a "Hotel Portal" root only ate horizontal space.
    expect(helper.hotel_breadcrumb_parts).to eq([
      { type: :section, label: "Reports" },
      { type: :menu, label: "Summary", path: "/reports", siblings: [ { label: "Summary", path: "/reports" } ] }
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
