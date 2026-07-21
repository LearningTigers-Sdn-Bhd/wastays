# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PanelsUI::Checkbox", type: :system do
  before { visit_when_loaded "/system-design?only=checkbox_preview" }

  it "renders the checkbox showcase in both themes" do
    expect(page).to have_css("#checkbox-preview-heading", text: "Checkboxes")
    expect(page).to have_css("[data-theme='panel-light'] .panel-checkbox", minimum: 6)
    expect(page).to have_css("[data-theme='panel-dark'] .panel-checkbox", minimum: 6)
    expect(page).to have_css("[data-theme='panel-light'] .panel-checkbox__label", text: "Send booking confirmation")
  end

  it "initializes and clears an indeterminate checkbox after user interaction" do
    checkbox = page.find("[data-theme='panel-light'] input[data-panels-ui--checkbox-indeterminate-value='true']")

    expect(page.evaluate_script("arguments[0].indeterminate", checkbox)).to be(true)

    checkbox.click

    expect(page.evaluate_script("arguments[0].indeterminate", checkbox)).to be(false)
  end

  it "centers the control against labels with descriptions and keeps the required marker on the label line" do
    geometry = page.evaluate_script(<<~JS)
      (() => {
        const root = document.querySelector("[data-theme='panel-light'] input[name$='[terms]']").closest(".panel-checkbox")
        const input = root.querySelector(".panel-checkbox__input").getBoundingClientRect()
        const content = root.querySelector(".panel-checkbox__content").getBoundingClientRect()
        const required = root.querySelector(".panel-checkbox__required")

        return {
          inputCenter: Math.round(input.top + input.height / 2),
          contentCenter: Math.round(content.top + content.height / 2),
          requiredParent: required.parentElement.className
        }
      })()
    JS

    expect(geometry.fetch("inputCenter")).to be_within(1).of(geometry.fetch("contentCenter"))
    expect(geometry.fetch("requiredParent")).to include("panel-checkbox__label")
  end

  it "distinguishes card borders from their containing surface and makes invalid titles destructive" do
    styles = page.evaluate_script(<<~JS)
      (() => {
        const theme = document.querySelector("[data-theme='panel-dark']")
        const selectedCard = theme.querySelector(".panel-checkbox[data-variant='card']:not([data-invalid='true'])")
        const invalidCard = theme.querySelector(".panel-checkbox[data-invalid='true']")

        return {
          cardBorder: getComputedStyle(selectedCard).borderTopColor,
          surfaceBorder: getComputedStyle(selectedCard.closest(".rounded-2xl")).borderTopColor,
          invalidLabel: getComputedStyle(invalidCard.querySelector(".panel-checkbox__label")).color,
          invalidError: getComputedStyle(invalidCard.querySelector(".panel-checkbox__error")).color
        }
      })()
    JS

    expect(styles.fetch("cardBorder")).not_to eq(styles.fetch("surfaceBorder"))
    expect(styles.fetch("invalidLabel")).to eq(styles.fetch("invalidError"))
  end

  it "uses a local focus-visible ring and an outlined checked state" do
    styles = page.evaluate_script(<<~JS)
      (() => {
        const theme = document.querySelector("[data-theme='panel-dark']")
        const checked = theme.querySelector("input[name$='[confirmation_copy]']")
        const sibling = theme.querySelector("input[name$='[terms]']")
        checked.focus()

        return {
          checkedBackground: getComputedStyle(checked).backgroundColor,
          uncheckedBackground: getComputedStyle(sibling).backgroundColor,
          outlineWidth: getComputedStyle(checked).outlineWidth
        }
      })()
    JS

    expect(styles.fetch("checkedBackground")).to eq(styles.fetch("uncheckedBackground"))
    expect(styles.fetch("outlineWidth").to_f).to be >= 2
  end
end
