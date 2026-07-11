# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Tabs, type: :component do
  def render_tabs(**opts)
    render_inline(described_class.new(**{ id: "t", default: "one" }.merge(opts))) do |t|
      t.with_tab(name: "one", label: "One", icon: "history", count: 5)
      t.with_tab(name: "two", label: "Two", show_subtab_breadcrumb: true)
      t.with_panel(name: "one") { "Panel one" }
      t.with_panel(name: "two") { "Panel two" }
    end
  end

  it "wires the controller root, values, and the breadcrumb outlet selector" do
    render_tabs(param: "section", level: :secondary, sync_url: false, breadcrumb_id: "page-breadcrumb")

    root = page.find("div.tabs-root[data-controller='panels-ui--tabs']")
    expect(root["data-panels-ui--tabs-param-value"]).to eq("section")
    expect(root["data-panels-ui--tabs-level-value"]).to eq("secondary")
    expect(root["data-panels-ui--tabs-sync-url-value"]).to eq("false")
    expect(root["data-panels-ui--tabs-active-value"]).to eq("one")
    expect(root["data-panels-ui--tabs-panels-ui--breadcrumb-outlet"]).to eq("#page-breadcrumb")
  end

  it "renders an accessible tablist of role=tab buttons" do
    render_tabs

    expect(page).to have_css("div.tabs-list[role='tablist']")
    expect(page).to have_css(
      "button#t-tab-one.tabs-tab[role='tab'][aria-controls='t-panel-one'][data-tab-name='one'][data-tab-label='One']" \
      "[data-panels-ui--tabs-target='tab']",
      text: "One"
    )
    expect(page).to have_css("button#t-tab-one .tabs-tab__count", text: "5")
    expect(page).to have_css("button#t-tab-two[data-show-subtab-breadcrumb='true']")
  end

  it "renders role=tabpanel panels linked back to their tab, hidden by default" do
    render_tabs

    expect(page).to have_css(
      "div#t-panel-one.tabs-panel.hidden[role='tabpanel'][aria-labelledby='t-tab-one'][data-tab-panel='one']",
      text: "Panel one", visible: :all
    )
    expect(page).to have_css("div#t-panel-two[role='tabpanel'][data-panels-ui--tabs-target='panel']", visible: :all)
  end

  it "works without panels (navigation-only tabs)" do
    render_inline(described_class.new(id: "nav", default: "a")) do |t|
      t.with_tab(name: "a", label: "A")
      t.with_tab(name: "b", label: "B")
    end

    expect(page).to have_css("div.tabs-list[role='tablist']")
    expect(page).to have_no_css(".tabs-panels")
  end

  it "omits breadcrumb outlet wiring when no breadcrumb id is supplied" do
    render_tabs

    expect(page.find("div.tabs-root")["data-panels-ui--tabs-panels-ui--breadcrumb-outlet"]).to be_nil
  end

  it "forwards container, id, data, and aria overrides while retaining defaults" do
    render_inline(described_class.new(
      id: "custom",
      list_class: "border-0",
      panels_class: "mt-8"
    )) do |tabs|
      tabs.with_tab(
        name: "one",
        label: "One",
        id: "legacy-tab",
        panel_id: "legacy-panel",
        data: { testid: "legacy-tab" },
        aria: { label: "First tab" }
      )
      tabs.with_panel(
        name: "one",
        id: "legacy-panel",
        tab_id: "legacy-tab",
        data: { testid: "legacy-panel" },
        aria: { label: "First panel" }
      ) { "Panel" }
    end

    expect(page).to have_css(".tabs-list.border-0")
    expect(page).to have_css(".tabs-panels.mt-8")
    expect(page).to have_css(
      "#legacy-tab[aria-controls='legacy-panel'][aria-label='First tab'][data-testid='legacy-tab']"
    )
    expect(page).to have_css(
      "#legacy-panel[aria-labelledby='legacy-tab'][aria-label='First panel'][data-testid='legacy-panel']",
      visible: :all
    )
  end
end
