# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PanelsUI::Popover", type: :system do
  before { visit "/system-design" }

  it "opens on trigger click and closes again on a second click" do
    click_button "Open popover"
    expect(page).to have_css("[role='dialog']:popover-open", text: "Dimensions")

    click_button "Open popover"
    expect(page).to have_no_css("[role='dialog']:popover-open", text: "Dimensions")
  end

  it "closes on Escape and restores focus to the trigger" do
    click_button "Open popover"
    expect(page).to have_css("[role='dialog']:popover-open", text: "Dimensions")

    dispatch_key("Escape")
    expect(page).to have_no_css("[role='dialog']:popover-open", text: "Dimensions")
    expect(page.evaluate_script("document.activeElement.id")).to eq("popover-default-trigger")
  end

  it "closes on an outside pointer press" do
    click_button "Open popover"
    expect(page).to have_css("[role='dialog']:popover-open", text: "Dimensions")

    find("h1", text: "PanelsUI").click
    expect(page).to have_no_css("[role='dialog']:popover-open", text: "Dimensions")
  end

  it "keeps the popover open while interacting with its content" do
    click_button "Focus trap"
    expect(page).to have_css("[role='dialog']:popover-open", text: "Rename layer")

    find("#popover-focus-name").set("Cover")
    expect(page).to have_css("[role='dialog']:popover-open", text: "Rename layer")
    expect(page.find("#popover-focus-name").value).to eq("Cover")
  end

  it "positions the arrow against the trigger side once shown" do
    click_button "Open popover"
    expect(page).to have_css("[role='dialog']:popover-open", text: "Dimensions")

    # Default placement is bottom, so Floating UI pins the arrow to the panel's top edge.
    arrow_top = page.evaluate_script(<<~JS)
      document.querySelector("[role='dialog']:popover-open .floating-arrow").style.top
    JS
    expect(arrow_top).to match(/-?\d/)
  end

  it "reveals on hover for the hover trigger variant" do
    find_button("Hover").hover
    expect(page).to have_css("[role='dialog']:popover-open", text: "Opens on hover")

    find("h1", text: "PanelsUI").hover
    expect(page).to have_no_css("[role='dialog']:popover-open", text: "Opens on hover")
  end

  it "traps focus within a focus popover and returns it on Escape" do
    click_button "Focus trap"
    expect(page).to have_css("[role='dialog']:popover-open", text: "Rename layer")

    # Focus has moved into the panel (the trap's first tabbable).
    expect(page.evaluate_script("document.querySelector('[role=dialog]:popover-open').contains(document.activeElement)")).to be(true)

    dispatch_key("Escape")
    expect(page).to have_no_css("[role='dialog']:popover-open", text: "Rename layer")
    expect(page.evaluate_script("document.activeElement.id")).to eq("popover-focus-trigger")
  end

  it "closes an open dropdown menu when a popover opens (shared layer channel)" do
    wait_for_stimulus_controller("#sd-dropdown", "panels-ui--dropdown-menu")
    wait_for_stimulus_controller("#popover-default-trigger", "panels-ui--popover")

    # Query and click atomically because Floating UI can invalidate a previously
    # captured element handle while positioning the full preview catalogue.
    click_via_javascript("#sd-dropdown-trigger")
    expect(page).to have_css("[role='menu']:popover-open")

    # The open menu overlaps the popover trigger, so dispatch the click directly rather
    # than hit-testing through the top-layer menu.
    click_via_javascript("#popover-default-trigger")
    expect(page).to have_css("[role='dialog']:popover-open", text: "Dimensions")
    expect(page).to have_no_css("[role='menu']:popover-open")
  end
end
