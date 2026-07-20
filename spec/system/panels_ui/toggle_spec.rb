# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PanelsUI toggle controls", type: :system do
  before { visit "/system-design" }

  def light_toggle
    find("[data-theme='panel-light'] input[name='toggle_panel_light[rates]']", visible: :all)
      .find(:xpath, "parent::span")
      .find("button")
  end

  def density_group
    find("#toggle_group_panel_light-density")
  end

  def formatting_group
    find("#toggle_group_panel_light-formatting")
  end

  def send_key(key)
    page.execute_script(<<~JS)
      document.activeElement.dispatchEvent(new KeyboardEvent("keydown", { key: #{key.to_json}, bubbles: true }))
    JS
  end

  it "toggles pressed state, the form value, native events, and its custom event" do
    input = find("input[name='toggle_panel_light[rates]']", visible: :all)
    page.execute_script(<<~JS, input)
      window.toggleProbe = { input: 0, change: 0, custom: [] }
      arguments[0].addEventListener("input", () => window.toggleProbe.input += 1)
      arguments[0].addEventListener("change", () => window.toggleProbe.change += 1)
      document.addEventListener("panels-ui--toggle:change", (event) => {
        window.toggleProbe.custom.push({ pressed: event.detail.pressed, value: event.detail.value })
      })
    JS

    expect(light_toggle["aria-pressed"]).to eq("true")
    light_toggle.click

    expect(light_toggle["aria-pressed"]).to eq("false")
    expect(light_toggle["data-state"]).to eq("off")
    expect(input.value).to eq("0")
    expect(page.evaluate_script("window.toggleProbe")).to eq(
      "input" => 1,
      "change" => 1,
      "custom" => [ { "pressed" => false, "value" => "0" } ]
    )
    expect(page).to have_css("[data-theme='panel-light'] output", text: "Current value: 0")
  end

  it "activates a focused toggle with Space and Enter and leaves disabled toggles unchanged" do
    toggle = find("[data-theme='panel-light'] button", text: "Restrictions")
    page.execute_script("arguments[0].focus()", toggle)
    page.driver.browser.keyboard.type(:space)
    expect(toggle["aria-pressed"]).to eq("true")

    page.driver.browser.keyboard.type(:enter)
    expect(toggle["aria-pressed"]).to eq("false")

    disabled = find("[data-theme='panel-light'] button", text: "Locked on")
    expect(disabled).to be_disabled
    expect(disabled["aria-pressed"]).to eq("true")
  end

  it "enforces required single selection and synchronizes its hidden value" do
    comfortable = density_group.find("button[data-value='comfortable']")
    compact = density_group.find("button[data-value='compact']")
    input = density_group.find("input[type='hidden']", visible: :all)

    comfortable.click
    expect(comfortable["aria-pressed"]).to eq("true")

    compact.click
    expect(compact["aria-pressed"]).to eq("true")
    expect(comfortable["aria-pressed"]).to eq("false")
    expect(input.value).to eq("compact")

    compact.click
    expect(compact["aria-pressed"]).to eq("true")
    expect(input.value).to eq("compact")
  end

  it "supports multiple selection and Rails array hidden fields" do
    bold = formatting_group.find("button[data-value='bold']")
    italic = formatting_group.find("button[data-value='italic']")
    bold_input = formatting_group.find("input[data-value='bold']", visible: :all)
    italic_input = formatting_group.find("input[data-value='italic']", visible: :all)

    italic.click
    expect(bold["aria-pressed"]).to eq("true")
    expect(italic["aria-pressed"]).to eq("true")
    expect(bold_input.disabled?).to be(false)
    expect(italic_input.disabled?).to be(false)
    expect(page).to have_css("[data-theme='panel-light'] output", text: "Current value: bold, italic")

    bold.click
    expect(bold["aria-pressed"]).to eq("false")
    expect(bold_input.disabled?).to be(true)
    expect(italic_input.disabled?).to be(false)
  end

  it "moves roving focus with arrows and Home/End while skipping disabled items" do
    compact = density_group.find("button[data-value='compact']")
    comfortable = density_group.find("button[data-value='comfortable']")
    spacious = density_group.find("button[data-value='spacious']")
    page.execute_script("arguments[0].focus()", comfortable)

    send_key("ArrowRight")
    expect(page.evaluate_script("document.activeElement.dataset.value")).to eq("compact")
    expect(spacious["tabindex"]).to eq("-1")

    send_key("End")
    expect(page.evaluate_script("document.activeElement.dataset.value")).to eq("comfortable")

    send_key("Home")
    expect(page.evaluate_script("document.activeElement.dataset.value")).to eq("compact")

    send_key("ArrowDown")
    expect(page.evaluate_script("document.activeElement.dataset.value")).to eq("compact")
  end

  it "uses vertical and RTL-aware arrow navigation" do
    vertical = find("#toggle_group_panel_light-alignment")
    start = vertical.find("button[data-value='start']")
    page.execute_script("arguments[0].focus()", start)
    send_key("ArrowDown")
    expect(page.evaluate_script("document.activeElement.dataset.value")).to eq("center")
    send_key("ArrowUp")
    expect(page.evaluate_script("document.activeElement.dataset.value")).to eq("start")

    page.execute_script("document.getElementById('toggle_group_panel_light-density').setAttribute('dir', 'rtl')")
    page.execute_script(
      "document.querySelector(\"#toggle_group_panel_light-density button[data-value='compact']\").focus()"
    )
    send_key("ArrowRight")
    expect(page.evaluate_script("document.activeElement.dataset.value")).to eq("comfortable")
  end

  it "dispatches native and custom group events with the selected value" do
    input = density_group.find("input[type='hidden']", visible: :all)
    page.execute_script(<<~JS, input)
      window.groupProbe = { input: 0, change: 0, custom: [] }
      arguments[0].addEventListener("input", () => window.groupProbe.input += 1)
      arguments[0].addEventListener("change", () => window.groupProbe.change += 1)
      document.addEventListener("panels-ui--toggle-group:change", (event) => {
        window.groupProbe.custom.push({ type: event.detail.type, value: event.detail.value })
      })
    JS

    density_group.find("button[data-value='compact']").click

    expect(page.evaluate_script("window.groupProbe")).to eq(
      "input" => 1,
      "change" => 1,
      "custom" => [ { "type" => "single", "value" => "compact" } ]
    )
  end
end
