# frozen_string_literal: true

require "rails_helper"

# Interactive coverage for the native-<dialog> Stimulus behavior. Runs against the
# in-app /system-design showcase, so Stimulus + Tailwind are live. Skipped
# automatically when no Chrome binary is present (see spec/rails_helper.rb).
RSpec.describe "PanelsUI::Dialog", type: :system do
  before { visit "/system-design" }

  it "opens via the trigger and moves focus to the title, not the close button" do
    expect(page).to have_no_css("dialog[open]")
    click_button "Open dialog"
    expect(page).to have_css("dialog#sd-dialog[open]")
    # Focus is inside the dialog, on meaningful static content at the top.
    focused_in_dialog = page.evaluate_script("document.getElementById('sd-dialog').contains(document.activeElement)")
    expect(focused_in_dialog).to be(true)
    on_title = page.evaluate_script("document.activeElement.matches('[data-panels-ui--dialog-target=initialFocus]')")
    expect(on_title).to be(true)
    expect(page.evaluate_script("document.activeElement.getAttribute('aria-label')")).not_to eq("Close")
  end

  it "closes on Escape" do
    click_button "Open dialog"
    expect(page).to have_css("dialog#sd-dialog[open]")
    find("dialog#sd-dialog").send_keys(:escape)
    expect(page).to have_no_css("dialog[open]")
  end

  it "closes on backdrop click" do
    click_button "Open dialog"
    expect(page).to have_css("dialog[open]")
    # A backdrop click on a native <dialog> targets the dialog element itself.
    page.execute_script("document.getElementById('sd-dialog').dispatchEvent(new MouseEvent('click', { bubbles: true }))")
    expect(page).to have_no_css("dialog[open]", wait: 2)
  end

  it "stacks dialogs in strict LIFO order and keeps body scroll locked" do
    original_overflow = page.evaluate_script("document.body.style.overflow")

    click_button "Open dialog"
    click_button "Review permissions"

    expect(page).to have_css("dialog#sd-dialog[open]")
    expect(page).to have_css("dialog#sd-dialog-confirm[open]")
    expect(page.evaluate_script("document.body.style.overflow")).to eq("hidden")
    expect(page.evaluate_script("document.activeElement.closest('dialog')?.id")).to eq("sd-dialog-confirm")

    # A synthetic backdrop event on the lower dialog must not bypass LIFO order.
    page.execute_script(<<~JS)
      document.getElementById("sd-dialog").dispatchEvent(new MouseEvent("click", { bubbles: true }))
    JS
    expect(page).to have_css("dialog#sd-dialog[open]")
    expect(page).to have_css("dialog#sd-dialog-confirm[open]")

    # A lower dialog's supported close action is also ignored while covered.
    page.execute_script("document.querySelector('#sd-dialog [data-action$=\"#close\"]').click()")
    expect(page).to have_css("dialog#sd-dialog[open]")
    expect(page).to have_css("dialog#sd-dialog-confirm[open]")

    click_button "Back to invitation"

    expect(page).to have_no_css("dialog#sd-dialog-confirm[open]")
    expect(page).to have_css("dialog#sd-dialog[open]")
    expect(page.evaluate_script("document.body.style.overflow")).to eq("hidden")
    expect(page.evaluate_script("document.activeElement.id")).to eq("sd-dialog-stack-trigger")

    click_button "Cancel"

    expect(page).to have_no_css("dialog[open]")
    expect(page.evaluate_script("document.body.style.overflow")).to eq(original_overflow)
  end

  it "keeps the remaining overlay locked if a background dialog is closed outside the supported API" do
    original_overflow = page.evaluate_script("document.body.style.overflow")

    click_button "Open dialog"
    click_button "Review permissions"
    page.execute_script("document.getElementById('sd-dialog').close()")

    expect(page).to have_no_css("dialog#sd-dialog[open]")
    expect(page).to have_css("dialog#sd-dialog-confirm[open]")
    expect(page.evaluate_script("document.body.style.overflow")).to eq("hidden")

    click_button "Back to invitation"

    expect(page).to have_no_css("dialog[open]")
    expect(page.evaluate_script("document.body.style.overflow")).to eq(original_overflow)
  end

  it "honors dismissible: false — Escape does not close the bare dialog" do
    click_button "Open bare (non-dismissible)"
    expect(page).to have_css("dialog#sd-dialog-bare[open]")
    find("dialog#sd-dialog-bare").send_keys(:escape)
    expect(page).to have_css("dialog#sd-dialog-bare[open]") # still open
    click_button "Got it"
    expect(page).to have_no_css("dialog#sd-dialog-bare[open]")
  end
end
