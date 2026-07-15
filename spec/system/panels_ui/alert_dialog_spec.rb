# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PanelsUI::AlertDialog", type: :system do
  before { visit "/system-design" }

  it "focuses cancel and only closes through an explicit response" do
    click_button "Basic"

    expect(page).to have_css("dialog#sd-alert-dialog-basic[open]")
    expect(page.evaluate_script("document.activeElement.dataset.slot")).to eq("alert-dialog-cancel")

    find("dialog#sd-alert-dialog-basic").send_keys(:escape)
    expect(page).to have_css("dialog#sd-alert-dialog-basic[open]")

    page.execute_script(<<~JS)
      document.getElementById("sd-alert-dialog-basic")
        .dispatchEvent(new MouseEvent("click", { bubbles: true }))
    JS
    expect(page).to have_css("dialog#sd-alert-dialog-basic[open]")

    within("dialog#sd-alert-dialog-basic") { click_button "Cancel" }
    expect(page).to have_no_css("dialog#sd-alert-dialog-basic[open]")
    expect(page.evaluate_script("document.activeElement.textContent.trim()")).to eq("Basic")
  end

  it "closes from the action response" do
    click_button "Basic"
    within("dialog#sd-alert-dialog-basic") { click_button "Continue" }

    expect(page).to have_no_css("dialog#sd-alert-dialog-basic[open]")
  end

  it "keeps stacked overlays in LIFO order and preserves the scroll lock" do
    original_overflow = page.evaluate_script("document.body.style.overflow")

    click_button "Open dialog"
    page.execute_script("document.getElementById('sd-alert-dialog-basic').showModal()")

    expect(page).to have_css("dialog#sd-dialog[open]")
    expect(page).to have_css("dialog#sd-alert-dialog-basic[open]")
    expect(page.evaluate_script("document.body.style.overflow")).to eq("hidden")

    page.execute_script(<<~JS)
      document.getElementById("sd-dialog")
        .dispatchEvent(new MouseEvent("click", { bubbles: true }))
    JS
    expect(page).to have_css("dialog#sd-dialog[open]")

    within("dialog#sd-alert-dialog-basic") { click_button "Cancel" }
    expect(page).to have_no_css("dialog#sd-alert-dialog-basic[open]")
    expect(page).to have_css("dialog#sd-dialog[open]")
    expect(page.evaluate_script("document.body.style.overflow")).to eq("hidden")

    within("dialog#sd-dialog") { click_button "Cancel" }
    expect(page.evaluate_script("document.body.style.overflow")).to eq(original_overflow)
  end

  it "maps Turbo metadata into the shared host and resolves cancel and confirm" do
    open_turbo_confirmation(
      message: "This cannot be undone.",
      attributes: {
        turboConfirmTitle: "Delete record?",
        turboConfirmTone: "warning",
        turboConfirmColor: "red"
      }
    )

    expect(page).to have_css("dialog#turbo-confirm-dialog[open][data-tone='warning']")
    expect(page).to have_css("#turbo-confirm-dialog [data-slot='alert-dialog-title']", text: "Delete record?")
    expect(page).to have_css("#turbo-confirm-dialog [data-slot='alert-dialog-description']", text: "This cannot be undone.")
    expect(page).to have_css("#turbo-confirm-button[data-variant='warning']")
    expect(page).to have_css("#turbo-cancel-button[data-variant='ghost']")

    click_button "Cancel"
    expect(page).to have_no_css("dialog#turbo-confirm-dialog[open]")
    expect(page.evaluate_script("window.turboConfirmResult")).to eq(false)

    open_turbo_confirmation(message: "Continue?", attributes: { turboConfirmColor: "green" })
    expect(page).to have_css("dialog#turbo-confirm-dialog[open][data-tone='success']")
    click_button "Confirm"
    expect(page.evaluate_script("window.turboConfirmResult")).to eq(true)
  end

  it "gates an actual Turbo form submission until the user confirms" do
    click_button "Test Turbo confirmation"
    expect(page).to have_css("dialog#turbo-confirm-dialog[open][data-tone='info']")

    within("dialog#turbo-confirm-dialog") { click_button "Cancel" }
    expect(URI.decode_www_form(URI.parse(page.current_url).query.to_s)).not_to include([ "turbo_confirmed", "1" ])

    click_button "Test Turbo confirmation"
    within("dialog#turbo-confirm-dialog") { click_button "Confirm" }
    expect(page).to have_current_path(/turbo_confirmed=1/, url: true)
  end

  it "supports the legacy split title/message contract and destructive color" do
    open_turbo_confirmation(
      message: "Revoke access?",
      attributes: {
        turboConfirmText: "The user will no longer be able to access this property.",
        turboConfirmColor: "red"
      }
    )

    expect(page).to have_css("dialog#turbo-confirm-dialog[open][data-tone='destructive']")
    expect(page).to have_css("#turbo-confirm-dialog [data-slot='alert-dialog-title']", text: "Revoke access?")
    expect(page).to have_css(
      "#turbo-confirm-dialog [data-slot='alert-dialog-description']",
      text: "The user will no longer be able to access this property."
    )
    expect(page).to have_css("#turbo-confirm-button[data-variant='destructive']")
    expect(page).to have_css("#turbo-cancel-button[data-variant='ghost']")
  end

  it "reinstalls one Turbo handler after a Turbo page replacement" do
    visit "/system-design"
    open_turbo_confirmation(message: "Still connected?", attributes: {})

    click_button "Cancel"
    expect(page.evaluate_script("window.turboConfirmResult")).to eq(false)
    expect(page).to have_no_css("dialog#turbo-confirm-dialog[open]")
  end

  def open_turbo_confirmation(message:, attributes:)
    page.execute_script(<<~JS)
      const form = document.createElement("form")
      const source = document.createElement("button")
      Object.assign(source.dataset, #{attributes.to_json})
      window.turboConfirmResult = "pending"
      Turbo.config.forms.confirm(#{message.to_json}, form, source).then((result) => {
        window.turboConfirmResult = result
      })
    JS
  end
end
