# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PanelsUI::Sheet", type: :system do
  before { visit_when_loaded "/system-design?only=sheet_preview" }

  it "opens from the right, focuses its title, and animates explicit close" do
    original_overflow = page.evaluate_script("document.body.style.overflow")

    click_button "Open right sheet"

    expect(page).to have_css("dialog#sd-sheet-right[open][data-panels-open]")
    expect(page.evaluate_script("document.activeElement.closest('dialog')?.id")).to eq("sd-sheet-right")
    expect(page.evaluate_script("document.body.style.overflow")).to eq("hidden")
    expect(page.evaluate_script("getComputedStyle(document.getElementById('sd-sheet-right')).transitionDuration")).to eq("0.3s")

    still_open = page.evaluate_script(<<~JS)
      (() => {
        document.querySelector("#sd-sheet-right [data-action='panels-ui--sheet#close']").click()
        return document.getElementById("sd-sheet-right").open
      })()
    JS
    expect(still_open).to be(true)
    expect(page).to have_no_css("dialog#sd-sheet-right[open]")
    expect(page).to have_no_css("body[style*='overflow: hidden']")
    expect(page.evaluate_script("document.body.style.overflow")).to eq(original_overflow)
  end

  it "opens and closes a vertical sheet with Escape" do
    click_button "Open bottom sheet"

    expect(page).to have_css("dialog#sd-sheet-bottom[open][data-panels-open]")
    find("dialog#sd-sheet-bottom").send_keys(:escape)
    expect(page).to have_no_css("dialog#sd-sheet-bottom[open]")
  end

  it "renders the floating variant inside a rounded viewport frame" do
    arm_transition_wait("#sd-sheet-floating", property: "translate")
    click_button "Open floating sheet"

    expect(page).to have_css("dialog#sd-sheet-floating[open][data-panels-open]")
    wait_for_transition_end("#sd-sheet-floating")
    geometry = page.evaluate_script(<<~JS)
      (() => {
        const sheet = document.getElementById("sd-sheet-floating")
        const rect = sheet.getBoundingClientRect()
        return {
          top: Math.round(rect.top),
          left: Math.round(rect.left),
          bottom: Math.round(window.innerHeight - rect.bottom),
          radius: getComputedStyle(sheet).borderTopLeftRadius
        }
      })()
    JS

    expect(geometry).to include("top" => 16, "left" => 16, "bottom" => 16)
    expect(geometry.fetch("radius")).not_to eq("0px")
  end

  it "animates backdrop dismissal" do
    click_button "Open left sheet"
    expect(page).to have_css("dialog#sd-sheet-left[open][data-panels-open]")

    page.execute_script(<<~JS)
      document.getElementById("sd-sheet-left").dispatchEvent(new MouseEvent("click", { bubbles: true }))
    JS

    expect(page).to have_no_css("dialog#sd-sheet-left[open]")
  end

  it "honors dismissible: false" do
    click_button "Open required sheet"
    expect(page).to have_css("dialog#sd-sheet-required[open]")

    find("dialog#sd-sheet-required").send_keys(:escape)
    page.execute_script(<<~JS)
      document.getElementById("sd-sheet-required").dispatchEvent(new MouseEvent("click", { bubbles: true }))
    JS

    expect(page).to have_css("dialog#sd-sheet-required[open]")
    click_in_overlay "Finish required step"
    expect(page).to have_no_css("dialog#sd-sheet-required[open]")
  end

  it "closes immediately when reduced motion is requested" do
    page.execute_script(<<~JS)
      window.matchMedia = (query) => ({
        matches: query === "(prefers-reduced-motion: reduce)",
        media: query,
        addEventListener: () => {},
        removeEventListener: () => {}
      })
    JS
    click_button "Open top sheet"
    expect(page).to have_css("dialog#sd-sheet-top[open][data-panels-open]")

    still_open = page.evaluate_script(<<~JS)
      (() => {
        document.querySelector("#sd-sheet-top [data-action='panels-ui--sheet#close']").click()
        return document.getElementById("sd-sheet-top").open
      })()
    JS

    expect(still_open).to be(false)
  end

  it "stacks sibling sheets in strict LIFO order" do
    original_overflow = page.evaluate_script("document.body.style.overflow")

    click_button "Open right sheet"
    click_in_overlay "Open stacked sheet"

    expect(page).to have_css("dialog#sd-sheet-right[open]")
    expect(page).to have_css("dialog#sd-sheet-stacked[open][data-panels-open]")
    expect(page.evaluate_script("document.activeElement.closest('dialog')?.id")).to eq("sd-sheet-stacked")

    page.execute_script(<<~JS)
      document.getElementById("sd-sheet-right").dispatchEvent(new MouseEvent("click", { bubbles: true }))
      document.querySelector("#sd-sheet-right [data-action='panels-ui--sheet#close']").click()
    JS

    expect(page).to have_css("dialog#sd-sheet-right[open]")
    expect(page).to have_css("dialog#sd-sheet-stacked[open]")

    click_in_overlay "Back to filters"

    expect(page).to have_no_css("dialog#sd-sheet-stacked[open]")
    expect(page).to have_css("dialog#sd-sheet-right[open]")
    expect(page.evaluate_script("document.body.style.overflow")).to eq("hidden")
    expect(page.evaluate_script("document.activeElement.id")).to eq("sd-sheet-stack-trigger")

    click_in_overlay "Cancel filters"

    expect(page).to have_no_css("dialog[open]")
    expect(page).to have_no_css("body[style*='overflow: hidden']")
    expect(page.evaluate_script("document.body.style.overflow")).to eq(original_overflow)
  end

  it "keeps cleanup safe after raw background close and Turbo-style removal" do
    click_button "Open right sheet"
    click_button "Open stacked sheet"
    page.execute_script("document.getElementById('sd-sheet-right').close()")

    expect(page).to have_no_css("dialog#sd-sheet-right[open]")
    expect(page).to have_css("dialog#sd-sheet-stacked[open]")
    expect(page.evaluate_script("document.body.style.overflow")).to eq("hidden")

    page.execute_script("document.getElementById('sd-sheet-stacked').remove()")

    expect(page).to have_no_css("dialog#sd-sheet-stacked")
    expect(page).to have_no_css("body[style*='overflow: hidden']")
  end
end
