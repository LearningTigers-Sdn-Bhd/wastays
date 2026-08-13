# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Tabs, type: :component do
  def render_panel_tabs(**options)
    render_inline(described_class.new(**{ id: "t", active: "one", aria_label: "Example sections" }.merge(options))) do |tabs|
      tabs.with_tab(name: "one", label: "One", icon: "history", count: 5)
      tabs.with_tab(name: "two", label: "Two")
      tabs.with_panel(name: "one") { "Panel one" }
      tabs.with_panel(name: "two") { "Panel two" }
    end
  end

  it "renders line-style panel tabs with accessible relationships by default" do
    render_panel_tabs

    expect(page).to have_css("#t.tabs-root--line[data-slot='tabs-root'][data-controller='panels-ui--tabs']")
    expect(page).to have_css(".tabs-list--line[role='tablist'][aria-label='Example sections'][data-slot='tabs-list']")
    expect(page).to have_css(
      "button#t-tab-one.tabs-tab--line[role='tab'][aria-controls='t-panel-one']" \
      "[aria-selected='true'][tabindex='0'][data-slot='tabs-trigger']",
      text: "One"
    )
    expect(page).to have_css("#t-tab-one .tabs-tab__count", text: "5")
    expect(page).to have_css(
      "#t-panel-one[role='tabpanel'][aria-labelledby='t-tab-one'][data-slot='tabs-panel']",
      text: "Panel one"
    )
    expect(page).to have_no_css("#t-panel-one[hidden]", visible: :all)
    expect(page).to have_css("#t-panel-two[hidden]", visible: :all)
  end

  it "renders pill styling only when explicitly requested" do
    render_panel_tabs(variant: :pill)

    expect(page).to have_css("#t.tabs-root--pill .tabs-list--pill .tabs-tab--pill")
  end

  it "falls back to the first panel when active does not match" do
    render_panel_tabs(active: "missing")

    expect(page).to have_css("#t-tab-one[aria-selected='true']")
    expect(page).to have_no_css("#t-panel-one[hidden]", visible: :all)
  end

  it "opts into URL state with a single param value" do
    render_panel_tabs(url: { param: "section" })

    expect(page.find("#t")["data-panels-ui--tabs-param-value"]).to eq("section")
  end

  it "does not configure URL state by default" do
    render_panel_tabs

    expect(page.find("#t")["data-panels-ui--tabs-param-value"]).to be_nil
  end

  it "infers ordinary link navigation without tab roles or JavaScript" do
    render_inline(described_class.new(id: "nav", active: "details", aria_label: "Booking sections")) do |tabs|
      tabs.with_tab(name: "details", label: "Details", href: "/bookings/1?tab=details", data: { turbo_frame: "workspace" })
      tabs.with_tab(name: "folio", label: "Folio", href: "/bookings/1?tab=folio")
    end

    expect(page).to have_css("#nav[data-slot='tabs-root'] nav.tabs-list--line[aria-label='Booking sections']")
    expect(page).to have_css(
      "a#nav-tab-details[aria-current='page'][data-slot='tabs-trigger'][data-turbo-frame='workspace']",
      text: "Details"
    )
    expect(page).to have_no_css("#nav[data-controller]")
    expect(page).to have_no_css("#nav [role='tablist'], #nav [role='tab']")
  end

  it "renders a disabled navigation tab as inert without breaking href inference" do
    render_inline(described_class.new(id: "nav", active: "taxes", aria_label: "Finance steps")) do |tabs|
      tabs.with_tab(name: "taxes", label: "1. Taxes and fees", href: "/onboarding/taxes")
      tabs.with_tab(name: "revenue", label: "2. Room revenue · Locked", disabled: true)
    end

    expect(page).to have_css("nav.tabs-list--line a#nav-tab-taxes[aria-current='page']")
    expect(page).to have_css(
      "span#nav-tab-revenue.tabs-tab--line[aria-disabled='true'][data-slot='tabs-trigger']",
      text: "2. Room revenue · Locked"
    )
    expect(page).to have_no_css("#nav-tab-revenue a, a#nav-tab-revenue")
  end

  it "keeps a disabled panel tab out of the tablist stops" do
    render_inline(described_class.new(id: "t", active: "one", aria_label: "Sections")) do |tabs|
      tabs.with_tab(name: "one", label: "One")
      tabs.with_tab(name: "two", label: "Two", disabled: true)
      tabs.with_panel(name: "one") { "Panel one" }
      tabs.with_panel(name: "two") { "Panel two" }
    end

    expect(page).to have_css("button#t-tab-one[role='tab']")
    expect(page).to have_css("span#t-tab-two[aria-disabled='true']")
    expect(page).to have_no_css("#t-tab-two[data-panels-ui--tabs-target='tab']")
  end

  it "falls back to the first enabled tab when active does not match" do
    render_inline(described_class.new(id: "t", active: "missing", aria_label: "Sections")) do |tabs|
      tabs.with_tab(name: "one", label: "One", disabled: true)
      tabs.with_tab(name: "two", label: "Two")
      tabs.with_panel(name: "one") { "Panel one" }
      tabs.with_panel(name: "two") { "Panel two" }
    end

    expect(page).to have_css("button#t-tab-two[aria-selected='true']")
    expect(page).to have_no_css("#t-panel-two[hidden]", visible: :all)
  end

  it "rejects a tab set with no enabled tab" do
    expect {
      render_inline(described_class.new(id: "t", aria_label: "Sections")) do |tabs|
        tabs.with_tab(name: "one", label: "One", disabled: true)
      end
    }.to raise_error(ArgumentError, /at least one enabled tab/)
  end

  it "renders no current navigation link when active is absent" do
    render_inline(described_class.new(id: "nav", aria_label: "Sections")) do |tabs|
      tabs.with_tab(name: "one", label: "One", href: "/one")
    end

    expect(page).to have_no_css("#nav [aria-current]")
  end

  it "forwards layout and slot overrides while retaining required attributes" do
    render_inline(described_class.new(
      id: "custom",
      active: "one",
      aria_label: "Custom sections",
      list_class: "border-0",
      panels_class: "mt-8"
    )) do |tabs|
      tabs.with_tab(
        name: "one",
        label: "One",
        id: "legacy-tab",
        panel_id: "legacy-panel",
        data: { testid: "legacy-tab" },
        aria: { label: "First tab" },
        class: "px-6"
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
    expect(page).to have_css("#legacy-tab.px-6[aria-controls='legacy-panel'][data-testid='legacy-tab']")
    expect(page).to have_css("#legacy-panel[aria-labelledby='legacy-tab'][data-testid='legacy-panel']")
  end

  validation_cases = {
    "empty tabs" => proc { |tabs| },
    "a missing accessible label" => proc { |tabs| tabs.with_tab(name: "one", label: "One", href: "/one") },
    "mixed links and buttons" => proc { |tabs|
      tabs.with_tab(name: "one", label: "One", href: "/one")
      tabs.with_tab(name: "two", label: "Two")
    },
    "panels on link navigation" => proc { |tabs|
      tabs.with_tab(name: "one", label: "One", href: "/one")
      tabs.with_panel(name: "one") { "Panel" }
    },
    "a missing matching panel" => proc { |tabs|
      tabs.with_tab(name: "one", label: "One")
    },
    "duplicate tab names" => proc { |tabs|
      tabs.with_tab(name: "one", label: "One", href: "/one")
      tabs.with_tab(name: "one", label: "Duplicate", href: "/duplicate")
    },
    "duplicate tab ids" => proc { |tabs|
      tabs.with_tab(name: "one", label: "One", href: "/one", id: "same")
      tabs.with_tab(name: "two", label: "Two", href: "/two", id: "same")
    }
  }

  validation_cases.each do |description, slots|
    it "rejects #{description}" do
      options = { id: "invalid", aria_label: "Sections" }
      options.delete(:aria_label) if description == "a missing accessible label"

      expect {
        render_inline(described_class.new(**options)) { |tabs| slots.call(tabs) }
      }.to raise_error(ArgumentError)
    end
  end

  it "rejects panel ids that do not reference each other" do
    expect {
      render_inline(described_class.new(id: "invalid", aria_label: "Sections")) do |tabs|
        tabs.with_tab(name: "one", label: "One", panel_id: "other-panel")
        tabs.with_panel(name: "one") { "Panel" }
      end
    }.to raise_error(ArgumentError, /reference each other/)
  end

  it "rejects an unsupported variant" do
    expect {
      render_inline(described_class.new(id: "invalid", variant: :underline, aria_label: "Sections")) do |tabs|
        tabs.with_tab(name: "one", label: "One", href: "/one")
      end
    }.to raise_error(ArgumentError, /variant/)
  end

  it "rejects an unknown active navigation key" do
    expect {
      render_inline(described_class.new(id: "invalid", active: "missing", aria_label: "Sections")) do |tabs|
        tabs.with_tab(name: "one", label: "One", href: "/one")
      end
    }.to raise_error(ArgumentError, /active navigation tab/)
  end

  it "rejects malformed URL configuration" do
    expect {
      render_inline(described_class.new(id: "invalid", url: { parameter: "tab" }, aria_label: "Sections")) do |tabs|
        tabs.with_tab(name: "one", label: "One", href: "/one")
      end
    }.to raise_error(ArgumentError, /url must be/)
  end

  it "rejects URL state on link navigation" do
    expect {
      render_inline(described_class.new(id: "invalid", url: { param: "tab" }, aria_label: "Sections")) do |tabs|
        tabs.with_tab(name: "one", label: "One", href: "/one")
      end
    }.to raise_error(ArgumentError, /link navigation cannot configure URL state/)
  end
end
