# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PanelsUI::FormField", type: :system do
  before { visit "/system-design" }

  def inline_geometry(theme)
    page.evaluate_script(<<~JS)
      (() => {
        const section = document.querySelector('[aria-labelledby="form-fields-preview-heading"]')
        const card = [...section.querySelectorAll(':scope > div > [data-theme]')]
          .find((element) => element.dataset.theme === '#{theme}')
        const input = card.querySelector('input[name$="[nightly_rate]"]')
        const group = input.closest('.panel-control-group')
        const start = group.querySelector('[data-align="inline-start"]')
        const end = group.querySelector('[data-align="inline-end"]')
        const rect = (element) => {
          const bounds = element.getBoundingClientRect()
          return { top: Math.round(bounds.top), bottom: Math.round(bounds.bottom), height: Math.round(bounds.height) }
        }

        return { group: rect(group), input: rect(input), start: rect(start), end: rect(end) }
      })()
    JS
  end

  it "keeps the input and both inline addons on one row in both themes" do
    %w[panel-light panel-dark].each do |theme|
      geometry = inline_geometry(theme)

      expect(geometry.fetch("start")).to include(
        "top" => geometry.dig("input", "top"),
        "bottom" => geometry.dig("input", "bottom")
      )
      expect(geometry.fetch("end")).to include(
        "top" => geometry.dig("input", "top"),
        "bottom" => geometry.dig("input", "bottom")
      )
      expect(geometry.dig("group", "height")).to be_between(
        geometry.dig("input", "height"),
        geometry.dig("input", "height") + 2
      )
    end
  end

  it "keeps start-only and end-only inline groups on one row" do
    %w[inline-end inline-start].each do |removed_alignment|
      geometry = page.evaluate_script(<<~JS)
        (() => {
          const section = document.querySelector('[aria-labelledby="form-fields-preview-heading"]')
          const card = [...section.querySelectorAll(':scope > div > [data-theme]')]
            .find((element) => element.dataset.theme === 'panel-light')
          const original = card.querySelector('input[name$="[nightly_rate]"]')
            .closest('.panel-control-group[data-layout="inline"]')
          const group = original.cloneNode(true)
          group.querySelector('[data-align="#{removed_alignment}"]').remove()
          original.after(group)

          const input = group.querySelector('.panel-input')
          const addon = group.querySelector('.panel-control-group__addon')
          const inputRect = input.getBoundingClientRect()
          const addonRect = addon.getBoundingClientRect()
          const result = {
            inputTop: Math.round(inputRect.top),
            inputBottom: Math.round(inputRect.bottom),
            addonTop: Math.round(addonRect.top),
            addonBottom: Math.round(addonRect.bottom)
          }
          group.remove()
          return result
        })()
      JS

      expect(geometry).to include(
        "addonTop" => geometry.fetch("inputTop"),
        "addonBottom" => geometry.fetch("inputBottom")
      )
    end
  end

  it "keeps block addons above and below the textarea" do
    geometry = page.evaluate_script(<<~JS)
      (() => {
        const section = document.querySelector('[aria-labelledby="form-fields-preview-heading"]')
        const card = [...section.querySelectorAll(':scope > div > [data-theme]')]
          .find((element) => element.dataset.theme === 'panel-light')
        const textarea = card.querySelector('textarea[name$="[notes]"]')
        const group = textarea.closest('.panel-control-group')
        const start = group.querySelector('[data-align="block-start"]').getBoundingClientRect()
        const control = textarea.getBoundingClientRect()
        const end = group.querySelector('[data-align="block-end"]').getBoundingClientRect()

        return {
          startBottom: Math.round(start.bottom),
          controlTop: Math.round(control.top),
          controlBottom: Math.round(control.bottom),
          endTop: Math.round(end.top)
        }
      })()
    JS

    expect(geometry.fetch("startBottom")).to eq(geometry.fetch("controlTop"))
    expect(geometry.fetch("endTop")).to eq(geometry.fetch("controlBottom"))
  end

  it "renders bare addons without separators and gives bordered textarea addons extra padding" do
    styles = page.evaluate_script(<<~JS)
      (() => {
        const section = document.querySelector('[aria-labelledby="form-fields-preview-heading"]')
        const card = [...section.querySelectorAll(':scope > div > [data-theme]')]
          .find((element) => element.dataset.theme === 'panel-light')
        const bare = card.querySelector('input[name$="[nightly_rate]"]')
          .closest('.panel-control-group')
          .querySelector('[data-variant="bare"]')
        const bordered = card.querySelector('textarea[name$="[notes]"]')
          .closest('.panel-control-group')
          .querySelector('[data-align="block-start"]')
        const bareStyle = getComputedStyle(bare)
        const borderedStyle = getComputedStyle(bordered)

        return {
          bareBorder: bareStyle.borderInlineEndWidth,
          borderedBorder: borderedStyle.borderBlockEndWidth,
          borderedPadding: parseFloat(borderedStyle.paddingBlockStart)
        }
      })()
    JS

    expect(styles.fetch("bareBorder")).to eq("0px")
    expect(styles.fetch("borderedBorder")).to eq("1px")
    expect(styles.fetch("borderedPadding")).to be >= 10
  end

  it "renders unique preview control ids with matching labels" do
    ids_and_labels = page.evaluate_script(<<~JS)
      (() => {
        const controls = [...document.querySelectorAll('#form-fields-preview-heading ~ * input, #form-fields-preview-heading ~ * textarea')]
        const ids = controls.map((control) => control.id)
        return {
          ids,
          labelsMatch: controls.every((control) => document.querySelector(`label[for="${control.id}"]`))
        }
      })()
    JS

    ids = ids_and_labels.fetch("ids")
    expect(ids).not_to be_empty
    expect(ids.uniq.length).to eq(ids.length)
    expect(ids_and_labels.fetch("labelsMatch")).to be(true)
  end
end
