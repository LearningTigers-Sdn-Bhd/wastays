# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PanelsUI feedback components", type: :system do
  before { visit_when_loaded "/system-design?only=alert_preview,banner_preview" }

  it "removes a dismissible alert until reload" do
    within("[data-testid='dismissible-alert']") { find("button[aria-label='Dismiss alert']").click }

    expect(page).to have_no_css("[data-testid='dismissible-alert']")
  end

  it "previews and dismisses a fixed top banner" do
    click_button "Preview fixed top"

    expect(page).to have_css("#preview-fixed-top-banner[data-strategy='fixed'][data-position='top']", visible: true)
    within("#preview-fixed-top-banner") { find("button[aria-label='Dismiss banner']").click }
    expect(page).to have_no_css("#preview-fixed-top-banner")

    click_button "Preview fixed top"
    expect(page).to have_css("#preview-fixed-top-banner", visible: true)
  end

  it "previews and dismisses a floating fixed bottom banner" do
    click_button "Preview fixed bottom"

    expect(page).to have_css(
      "#preview-fixed-bottom-banner[data-appearance='floating'][data-strategy='fixed'][data-position='bottom']",
      visible: true
    )
    within("#preview-fixed-bottom-banner") { find("button[aria-label='Dismiss banner']").click }
    expect(page).to have_no_css("#preview-fixed-bottom-banner")

    click_button "Preview fixed bottom"
    expect(page).to have_css("#preview-fixed-bottom-banner", visible: true)
  end
end
