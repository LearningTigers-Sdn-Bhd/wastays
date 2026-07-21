# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PanelsUI::Breadcrumb", type: :system do
  before { visit_when_loaded "/system-design?only=breadcrumb_preview" }

  let(:toggle) { find("button[aria-label='Open Financial navigation']") }

  def send_key(key)
    page.execute_script(<<~JS)
      document.activeElement.dispatchEvent(new KeyboardEvent("keydown", { key: #{key.to_json}, bubbles: true }))
    JS
  end

  it "opens the sibling menu on click and positions it in the top layer" do
    toggle.click

    expect(page).to have_css("[role='menu']:popover-open")
    expect(toggle["aria-expanded"]).to eq("true")
    expect(page).to have_link("Daily Revenue")
  end

  it "closes the menu on outside click" do
    toggle.click
    expect(page).to have_css("[role='menu']:popover-open")

    find("h1", text: "PanelsUI").click
    expect(page).to have_no_css("[role='menu']:popover-open")
    expect(toggle["aria-expanded"]).to eq("false")
  end

  it "closes the menu on Escape and restores focus to the trigger" do
    toggle.click
    expect(page).to have_css("[role='menu']:popover-open")

    send_key("Escape")
    expect(page).to have_no_css("[role='menu']:popover-open")
    expect(page).to have_css("button:focus[data-panels-ui--dropdown-menu-target='trigger']")
  end

  it "toggling the same trigger twice closes the menu" do
    toggle.click
    expect(page).to have_css("[role='menu']:popover-open")

    toggle.click
    expect(page).to have_no_css("[role='menu']:popover-open")
  end
end
