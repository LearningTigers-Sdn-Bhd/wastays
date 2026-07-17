# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PanelsUI::Toast", type: :system do
  before { visit "/system-design" }

  # Scope trigger clicks to the toast section: the button label "Info" otherwise
  # substring-matches the "Informational" button in the Button preview above it.
  def toast_preview(&) = within("section[aria-labelledby='toast-preview-heading']", &)

  it "creates RailsBlocks-style client-side toasts for semantic variants" do
    toast_preview { click_button "Danger" }

    expect(page).to have_css("#toast-viewport .toast[data-variant='danger'][role='alert']", text: "Payment failed")
    expect(page).to have_css("#toast-viewport .toast[data-variant='danger'] .toast__icon svg")
  end

  it "dismisses a toast when its close button is clicked" do
    toast_preview { click_button "Info" }
    within("#toast-viewport .toast") { find("button[aria-label='Dismiss notification']").click }

    expect(page).to have_no_css("#toast-viewport .toast")
  end

  it "exposes only the toast(message, options) API and auto-dismisses messages" do
    toast_id = page.evaluate_script(<<~JS)
      window.toast("Short-lived", { type: "default", duration: 300 })
    JS
    expect(page).to have_no_css("##{toast_id}", wait: 1)
    expect(page.evaluate_script("window.Toast")).to be_nil
  end
end
