# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PanelsUI::Tabs", type: :system do
  before { visit "/system-design" }

  let(:tablist) { find("#sd-tabs .tabs-list") }
  def tab(name) = find("#sd-tabs-tab-#{name}")

  def send_key(key)
    page.execute_script(<<~JS)
      document.activeElement.dispatchEvent(new KeyboardEvent("keydown", { key: #{key.to_json}, bubbles: true }))
    JS
  end

  it "activates the default tab and shows only its panel" do
    expect(tab("history")["aria-selected"]).to eq("true")
    expect(tab("history")["tabindex"]).to eq("0")
    expect(page).to have_css("#sd-tabs-panel-history:not(.hidden)")
    expect(page).to have_css("#sd-tabs-panel-advanced.hidden", visible: :all)
  end

  it "switches panel and roving tabindex on click" do
    tab("advanced").click

    expect(tab("advanced")["aria-selected"]).to eq("true")
    expect(tab("advanced")["tabindex"]).to eq("0")
    expect(tab("history")["tabindex"]).to eq("-1")
    expect(page).to have_css("#sd-tabs-panel-advanced:not(.hidden)")
    expect(page).to have_css("#sd-tabs-panel-history.hidden", visible: :all)
  end

  it "navigates and activates with arrow keys and Home/End" do
    tab("history").click
    send_key("ArrowRight")
    expect(page).to have_css("#sd-tabs-tab-advanced[aria-selected='true']")

    send_key("End")
    expect(page).to have_css("#sd-tabs-tab-exports[aria-selected='true']")

    send_key("Home")
    expect(page).to have_css("#sd-tabs-tab-history[aria-selected='true']")
  end

  it "mirrors the active tab into the URL query param" do
    tab("exports").click
    expect(page).to have_current_path(/[?&]tab=exports/, url: true)
  end

  it "initializes from a valid query parameter without rewriting invalid values" do
    visit "/system-design?tab=exports"
    expect(page).to have_css("#sd-tabs-tab-exports[aria-selected='true']")

    visit "/system-design?tab=unknown"
    expect(page).to have_css("#sd-tabs-tab-history[aria-selected='true']")
    expect(page).to have_current_path("/system-design?tab=unknown")
  end

  it "drives the breadcrumb tab label and subtab segment through the outlet" do
    within("[data-testid='tabs-breadcrumb-demo']") do
      expect(page).to have_css("[data-panels-ui--breadcrumb-target='tabLabel']", text: "Calendar")
      expect(page).to have_css("[data-subtabs-breadcrumb-segment].hidden", visible: :all)

      find("#sd-tabs-linked-tab-bulk").click
      expect(page).to have_css("[data-panels-ui--breadcrumb-target='tabLabel']", text: "Bulk Edit")
      expect(page).to have_css("[data-subtabs-breadcrumb-segment]:not(.hidden)")

      find("#sd-subtabs-linked-tab-overrides").click
      expect(page).to have_css(
        "[data-panels-ui--breadcrumb-target='subtabLabel']",
        text: "Availability Overrides"
      )
    end
  end

  it "does not update unrelated breadcrumbs" do
    expect(page).to have_css(
      "#sd-unrelated-tabs-bc [data-panels-ui--breadcrumb-target='tabLabel']",
      text: "Calendar"
    )

    within("[data-testid='tabs-breadcrumb-demo']") do
      find("#sd-tabs-linked-tab-bulk").click
      expect(page).to have_css("[data-panels-ui--breadcrumb-target='tabLabel']", text: "Bulk Edit")
    end

    expect(page).to have_css(
      "#sd-unrelated-tabs-bc [data-panels-ui--breadcrumb-target='tabLabel']",
      text: "Calendar"
    )
  end
end
