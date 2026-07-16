# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PanelsUI::Accordion", type: :system do
  before { visit "/system-design" }

  def trigger(accordion, item)
    find("#sd-accordion-#{accordion}-item-#{item}-trigger")
  end

  def send_key(key)
    page.execute_script(<<~JS)
      document.activeElement.dispatchEvent(new KeyboardEvent("keydown", { key: #{key.to_json}, bubbles: true }))
    JS
  end

  it "renders both variants and the documented states" do
    expect(page).to have_css("#accordion-preview-heading", text: "Accordion")
    expect(page).to have_css("#sd-accordion-single.panel-accordion--default")
    expect(page).to have_css("#sd-accordion-multiple.panel-accordion--bordered")
    expect(page).to have_css("#sd-accordion-single-item-3-trigger[disabled]")
    expect(page).to have_css("#sd-accordion-required-item-1-trigger[aria-disabled='true']")
  end

  it "coordinates a single collapsible accordion" do
    first = trigger("single", 1)
    second = trigger("single", 2)

    expect(first["aria-expanded"]).to eq("true")
    second.click

    expect(first["aria-expanded"]).to eq("false")
    expect(second["aria-expanded"]).to eq("true")
    expect(page).to have_css("#sd-accordion-single-item-1-content[hidden]", visible: :all, wait: 1)

    second.click
    expect(second["aria-expanded"]).to eq("false")
    expect(page).to have_css("#sd-accordion-single [data-accordion-item][data-state='open']", count: 0)
  end

  it "keeps multiple items open independently" do
    billing = trigger("multiple", 3)
    billing.click

    expect(trigger("multiple", 1)["aria-expanded"]).to eq("true")
    expect(trigger("multiple", 2)["aria-expanded"]).to eq("true")
    expect(billing["aria-expanded"]).to eq("true")

    trigger("multiple", 1).click
    expect(trigger("multiple", 1)["aria-expanded"]).to eq("false")
    expect(trigger("multiple", 2)["aria-expanded"]).to eq("true")
    expect(billing["aria-expanded"]).to eq("true")
  end

  it "keeps one item open and moves the aria-disabled lock" do
    first = trigger("required", 1)
    second = trigger("required", 2)

    first.click
    expect(first["aria-expanded"]).to eq("true")

    second.click
    expect(first["aria-expanded"]).to eq("false")
    expect(first["aria-disabled"]).to be_nil
    expect(second["aria-expanded"]).to eq("true")
    expect(second["aria-disabled"]).to eq("true")
  end

  it "navigates direct enabled triggers with arrows, Home, and End" do
    first = trigger("single", 1)
    second = trigger("single", 2)
    page.execute_script("document.getElementById('#{first[:id]}').focus()")

    send_key("ArrowDown")
    expect(page.evaluate_script("document.activeElement.id")).to eq(second[:id])

    send_key("ArrowDown")
    expect(page.evaluate_script("document.activeElement.id")).to eq(first[:id])

    send_key("End")
    expect(page.evaluate_script("document.activeElement.id")).to eq(second[:id])

    send_key("Home")
    expect(page.evaluate_script("document.activeElement.id")).to eq(first[:id])

    send_key("ArrowUp")
    expect(page.evaluate_script("document.activeElement.id")).to eq(second[:id])
  end

  it "supports native Enter and Space activation" do
    second = trigger("single", 2)
    page.execute_script("arguments[0].focus()", second)
    page.driver.browser.keyboard.type(:enter)
    expect(second["aria-expanded"]).to eq("true")

    page.driver.browser.keyboard.type(:space)
    expect(second["aria-expanded"]).to eq("false")
  end

  it "isolates nested state and preserves it while the parent is closed" do
    parent = trigger("multiple", 2)
    nested = find("#sd-accordion-nested-item-1-trigger")
    nested.click

    expect(nested["aria-expanded"]).to eq("true")
    expect(trigger("multiple", 1)["aria-expanded"]).to eq("true")
    expect(parent["aria-expanded"]).to eq("true")

    page.execute_script("document.getElementById('sd-accordion-multiple-item-2-trigger').click()")
    expect(page.evaluate_script("document.activeElement.id")).to eq(parent[:id])
    expect(parent["aria-expanded"]).to eq("false")
    expect(nested["aria-expanded"]).to eq("true")

    parent.click
    expect(parent["aria-expanded"]).to eq("true")
    expect(nested["aria-expanded"]).to eq("true")
  end

  it "does not rotate a closed nested indicator when its parent is open" do
    nested_indicator = "#sd-accordion-nested-item-1-trigger .panel-accordion__indicator"
    expect(find("#sd-accordion-nested-item-1-trigger")["aria-expanded"]).to eq("false")

    transform = page.evaluate_script("getComputedStyle(document.querySelector('#{nested_indicator}')).transform")
    expect(transform).to eq("none")
  end

  it "does not animate when reduced motion is requested" do
    page.execute_script(<<~JS)
      window.matchMedia = () => ({ matches: true, addEventListener() {}, removeEventListener() {} })
    JS

    trigger("single", 2).click
    content = find("#sd-accordion-single-item-2-content")
    expect(content["data-collapsible-animate"]).to be_nil
    expect(page).to have_css("#sd-accordion-single-item-2-content:not([hidden])")
  end
end
