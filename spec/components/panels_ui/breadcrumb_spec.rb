# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Breadcrumb, type: :component do
  def render_breadcrumb(parts)
    render_inline(described_class.new(parts: parts, id: "bc"))
  end

  it "renders a semantic nav/ol wired to the controller" do
    render_breadcrumb([ { type: :section, label: "Operations" } ])

    expect(page).to have_css("nav[aria-label='Breadcrumb'][data-controller='panels-ui--breadcrumb'] > ol.breadcrumb-list")
    expect(page).to have_css("li.breadcrumb-item")
  end

  it "renders nothing when there are no parts" do
    render_inline(described_class.new(parts: []))
    expect(page).to have_no_css("nav")
  end

  it "renders section/menu_group as theme-token static text" do
    render_breadcrumb([ { type: :section, label: "Finance" }, { type: :menu_group, label: "AR" } ])

    expect(page).to have_css("span.cursor-default.font-medium.text-muted-foreground", text: "Finance")
    expect(page).to have_css("span.cursor-default.font-medium.text-muted-foreground", text: "AR")
  end

  it "links a non-last menu that has a path, and bolds the last part as current" do
    render_breadcrumb([
      { type: :menu, label: "Bookings", path: "/bookings" },
      { label: "BK-1" }
    ])

    expect(page).to have_link("Bookings", href: "/bookings")
    expect(page).to have_css("span.font-semibold.text-foreground", text: "BK-1")
  end

  it "delegates the sibling dropdown to panels-ui--dropdown-menu with menuitem links" do
    render_breadcrumb([
      { type: :menu, label: "Financial", path: "/f", siblings: [
        { label: "Summary", path: "/s" },
        { label: "Refunds", path: "/r" }
      ] }
    ])

    expect(page).to have_css("div.breadcrumb-dropdown.dropdown-menu-root[data-controller='panels-ui--dropdown-menu']")
    expect(page).to have_css(
      "button#bc-trigger-0.breadcrumb-dropdown__trigger[aria-controls='bc-menu-0'][aria-haspopup='menu']" \
      "[aria-label='Open Financial navigation'][data-panels-ui--dropdown-menu-target='trigger']"
    )
    expect(page).to have_link("Financial", href: "/f")
    expect(page).to have_css(
      "#bc-menu-0.dropdown-menu[role='menu'][popover='manual'][data-panels-ui--dropdown-menu-target='menu']",
      visible: :all
    )
    expect(page).to have_css(
      "a.dropdown-menu__item[role='menuitem'][data-dropdown-menu-kind='command']",
      text: "Summary", visible: :all
    )
    expect(page).to have_css("a.dropdown-menu__item[role='menuitem']", text: "Refunds", visible: :all)
  end

  it "marks the tab label with both the legacy hook and the Stimulus target" do
    render_breadcrumb([ { label: "Calendar", tab_label: true } ])

    expect(page).to have_css(
      "span[data-tabs-breadcrumb-label][data-panels-ui--breadcrumb-target='tabLabel']",
      text: "Calendar"
    )
  end

  it "marks the subtab segment and its label, honoring the hidden flag" do
    render_breadcrumb([
      { label: "Calendar", tab_label: true },
      { label: "Standard Room", subtab_label: true, hidden: true }
    ])

    segment = page.find("li[data-subtabs-breadcrumb-segment][data-panels-ui--breadcrumb-target='subtabSegment']", visible: :all)
    expect(segment[:class]).to include("hidden")
    expect(page).to have_css(
      "span[data-subtabs-breadcrumb-label][data-panels-ui--breadcrumb-target='subtabLabel']",
      text: "Standard Room",
      visible: :all
    )
  end
end
