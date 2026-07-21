# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PanelsUI::Collapsible", type: :system do
  before { visit_when_loaded "/system-design?only=collapsible_preview" }

  let(:root) { find("#sd-collapsible-panel-light") }
  let(:trigger) { find("#sd-collapsible-panel-light-trigger") }

  it "renders the showcase in both themes with closed, open, and disabled examples" do
    expect(page).to have_css("#collapsible-preview-heading", text: "Collapsible")
    expect(page).to have_css("[data-collapsible-preview-theme='panel-light'] .panel-collapsible", count: 3)
    expect(page).to have_css("[data-collapsible-preview-theme='panel-dark'] .panel-collapsible", count: 3)
    expect(page).to have_css("#sd-collapsible-open-panel-light[data-state='open']")
    expect(page).to have_css("#sd-collapsible-disabled-panel-light[data-disabled]")
  end

  it "toggles aria, state hooks, content visibility, and the indicator" do
    content_selector = "#sd-collapsible-panel-light-content"
    expect(trigger["aria-expanded"]).to eq("false")
    expect(page).to have_css("#{content_selector}[hidden]", visible: :all)

    trigger.click

    expect(root["data-state"]).to eq("open")
    expect(trigger["aria-expanded"]).to eq("true")
    expect(page).to have_css("#{content_selector}:not([hidden])[data-state='open']")
    transform = page.evaluate_script("getComputedStyle(document.querySelector('#sd-collapsible-panel-light .panel-collapsible__indicator')).transform")
    expect(transform).not_to eq("none")

    trigger.click

    expect(root["data-state"]).to eq("closed")
    expect(trigger["aria-expanded"]).to eq("false")
    expect(page).to have_css("#{content_selector}[hidden]", visible: :all, wait: 1)
  end

  it "returns focus to the trigger when content is collapsed" do
    trigger.click
    page.execute_script("document.querySelector('#sd-collapsible-panel-light-content a').focus()")
    expect(page.evaluate_script("document.activeElement.textContent.trim()")).to eq("Review guest profile")
    page.execute_script("document.getElementById('sd-collapsible-panel-light-trigger').click()")

    expect(page.evaluate_script("document.activeElement.id")).to eq("sd-collapsible-panel-light-trigger")
  end

  it "does not toggle a disabled disclosure" do
    disabled = find("#sd-collapsible-disabled-panel-light", visible: :all)
    page.execute_script("document.getElementById('sd-collapsible-disabled-panel-light-trigger').click()")

    expect(disabled["data-state"]).to eq("closed")
    expect(page).to have_css("#sd-collapsible-disabled-panel-light-content[hidden]", visible: :all)
  end

  it "dispatches a change event with the new controlled state" do
    page.execute_script(<<~JS)
      window.collapsibleChanges = []
      document.getElementById("sd-collapsible-panel-light").addEventListener(
        "panels-ui--collapsible:change",
        (event) => window.collapsibleChanges.push(event.detail.open)
      )
    JS

    trigger.click
    trigger.click

    expect(page.evaluate_script("window.collapsibleChanges")).to eq([ true, false ])
  end
end
