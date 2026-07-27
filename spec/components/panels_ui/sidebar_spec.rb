# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Sidebar, type: :component do
  let(:sections) do
    [
      PanelsUI::Navigation::Section.new(label: "Home", items: [
        PanelsUI::Navigation::Item.new(label: "Dashboard", path: "/dash", icon: "home", active: true, search_text: "Dashboard Home")
      ]),
      PanelsUI::Navigation::Section.new(label: "Ops", items: [
        PanelsUI::Navigation::Item.new(label: "Bookings", path: "/bookings", icon: "calendar"),
        PanelsUI::Navigation::Item.new(label: "Reports", icon: "chart", active: true, children: [
          PanelsUI::Navigation::Item.new(label: "Financial", path: "/reports/fin", active: true)
        ])
      ])
    ]
  end

  def render_sidebar(**opts)
    render_inline(described_class.new(**{ key: "hotel", home_path: "/", sections: sections }.merge(opts)))
  end

  it "renders the desktop aside and mobile Sheet wired to their controllers" do
    render_sidebar

    expect(page).to have_css("aside#hotel-sidebar.panel-sidebar[data-collapsed='true'][data-collapsible='true'][data-locked='false'][data-panels-ui--sidebar-key-value='hotel']")
    expect(page).to have_css("aside#hotel-sidebar [data-sidebar-presentation='collapsed']:not([hidden])", visible: :all)
    expect(page).to have_css("aside#hotel-sidebar[data-controller~='panels-ui--sidebar']")
    expect(page).to have_css("dialog#hotel-sidebar-mobile.panel-sidebar--mobile-sheet[data-controller='panels-ui--sheet']", visible: :all)
    expect(page).to have_css(
      "#hotel-sidebar-mobile [data-controller~='panels-ui--sidebar'][data-panels-ui--sidebar-surface-value='mobile']",
      visible: :all
    )
    expect(page).to have_no_css("#hotel-sidebar-overlay", visible: :all)
    expect(page).to have_no_css("aside#hotel-sidebar .panel-sidebar__tooltip", visible: :all)
  end

  it "renders sections, links, and marks the active item with aria-current" do
    render_sidebar

    within("aside#hotel-sidebar") do
      expect(page).to have_css(".panel-sidebar__section-label", text: "Home")
      expect(page).to have_css("a.panel-sidebar__link[href='/bookings']", text: "Bookings")
      expect(page).to have_css("a.panel-sidebar__link[href='/dash'][aria-current='page']", text: "Dashboard")
    end
  end

  it "renders an active parent as an open collapsible group with its child link" do
    render_sidebar

    group = page.find("#hotel-sidebar-desktop-section-1-item-1-collapsible[data-state='open']")
    expect(group).to have_css("button.panel-sidebar__group-trigger[aria-expanded='true']", text: "Reports")
    expect(group).to have_css("a.panel-sidebar__child[href='/reports/fin'][aria-current='page']", text: "Financial")
  end

  it "composes desktop groups and leaves from the shared primitives" do
    render_sidebar

    within("aside#hotel-sidebar") do
      expect(page).to have_css("[data-controller~='panels-ui--collapsible']")
      expect(page).to have_css("[data-controller='panels-ui--popover']", visible: :all)
      expect(page).to have_css("[data-controller='panels-ui--tooltip']", visible: :all)
      trigger = page.find("#hotel-sidebar-desktop-section-1-item-1-popover-trigger", visible: :all)
      expect(trigger[:class]).to include("panel-sidebar__link")
      expect(trigger[:class]).not_to include("panel-button")
      expect(trigger["data-variant"]).to be_nil
      expect(trigger["data-size"]).to be_nil
      root = trigger.find(:xpath, "ancestor::span[@data-controller='panels-ui--popover']", visible: :all)
      expect(root["data-panels-ui--popover-offset-value"]).to eq("4.0")
      expect(root["data-panels-ui--popover-close-delay-value"]).to eq("180")
      expect(page).to have_css("#hotel-sidebar-desktop-section-1-item-1-popover-panel .floating-arrow", visible: :all)
    end
  end

  it "renders mobile navigation without desktop-only floating primitives" do
    render_sidebar

    within(page.find("dialog#hotel-sidebar-mobile", visible: :all)) do
      expect(page).to have_css("[data-controller~='panels-ui--collapsible']", visible: :all)
      expect(page).to have_no_css("[data-controller='panels-ui--popover']", visible: :all)
      expect(page).to have_no_css("[data-controller='panels-ui--tooltip']", visible: :all)
    end
  end

  it "uses unique ids across desktop, collapsed, and mobile presentations" do
    render_sidebar

    ids = page.all("#hotel-sidebar [id], #hotel-sidebar-mobile [id]", visible: :all).map { |element| element[:id] }
    expect(ids).to eq(ids.uniq)
    expect(ids).to include(
      "hotel-sidebar-desktop-section-1-item-1-collapsible",
      "hotel-sidebar-desktop-section-1-item-1-popover-panel",
      "hotel-sidebar-mobile-section-1-item-1-collapsible"
    )
  end

  it "renders the search box and search targets only when searchable" do
    render_sidebar(searchable: true)
    within("aside#hotel-sidebar") do
      expect(page).to have_css("input#hotel-sidebar-search-desktop[data-panels-ui--sidebar-search-target='input']")
      expect(page).to have_css("[data-panels-ui--sidebar-search-target='section']")
      expect(page).to have_css("[data-panels-ui--sidebar-search-target='item'][data-search-text]", count: 3)
    end

    render_sidebar(searchable: false)
    expect(page).to have_no_css("input[type='search']")
  end

  it "does not render legacy details, tooltip, or flyout hooks" do
    render_sidebar

    expect(page).to have_no_css("aside.panel-sidebar details", visible: :all)
    expect(page).to have_no_css("[data-sidebar-tooltip], [data-flyout-open], [data-flyout-pinned]", visible: :all)
    expect(page).to have_no_css(".panel-sidebar__tooltip", visible: :all)
  end

  it "renders footer items and the header slot" do
    render_inline(described_class.new(key: "hotel", home_path: "/", sections: sections,
                                      footer_items: [ PanelsUI::Navigation::Item.new(label: "Help", path: "/help", icon: "help") ])) do |s|
      s.with_header { "<span class='brand'>Acme</span>".html_safe }
    end

    expect(page).to have_css("aside#hotel-sidebar .panel-sidebar__header .brand", text: "Acme")
    expect(page).to have_css("aside#hotel-sidebar .panel-sidebar__footer a[href='/help']", text: "Help")
  end

  it "adds the search controller and turbo-permanent flag when requested" do
    render_sidebar(searchable: true, permanent: true)

    aside = page.find("aside#hotel-sidebar")
    expect(aside["data-controller"]).to include("panels-ui--sidebar-search")
    expect(aside["data-turbo-permanent"]).not_to be_nil
  end


  it "omits collapsed presentations when collapsing is disabled" do
    render_sidebar(collapsible: false)

    expect(page).to have_css("#hotel-sidebar[data-collapsible='false']")
    expect(page).to have_no_css("#hotel-sidebar [data-sidebar-presentation='collapsed']", visible: :all)
    expect(page).to have_no_css("#hotel-sidebar [data-controller='panels-ui--popover']", visible: :all)
    expect(page).to have_no_css("#hotel-sidebar [data-controller='panels-ui--tooltip']", visible: :all)
  end

  it "preserves secure external-link attributes in every presentation" do
    external_child = PanelsUI::Navigation::Item.new(
      label: "Child docs", path: "/child-docs", external: true
    )
    external_sections = [
      PanelsUI::Navigation::Section.new(label: "Links", items: [
        PanelsUI::Navigation::Item.new(label: "Docs", path: "/docs", external: true),
        PanelsUI::Navigation::Item.new(label: "Resources", children: [ external_child ])
      ])
    ]
    external_footer = PanelsUI::Navigation::Item.new(label: "Support", path: "/support", external: true)

    render_inline(described_class.new(
      key: "external",
      home_path: "/",
      sections: external_sections,
      footer_items: [ external_footer ]
    ))

    [ "/docs", "/child-docs", "/support" ].each do |path|
      links = page.all("a[href='#{path}']", visible: :all)
      expect(links).not_to be_empty
      expect(links).to all(satisfy { |link| link[:target] == "_blank" && link[:rel] == "noopener noreferrer" })
    end
  end
end
