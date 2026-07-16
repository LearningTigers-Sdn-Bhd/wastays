# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PanelsUI::DatePicker", type: :system do
  before { visit "/system-design" }

  def picker_css(theme, attribute)
    section = '[aria-labelledby="date-picker-preview-heading"]'
    "#{section} > div > [data-theme=\"#{theme}\"] input[name$=\"[#{attribute}]\"]"
  end

  it "enhances pickers and disables the trigger on a disabled field" do
    expect(page).to have_css("#{picker_css('panel-light', 'stay_date')}", visible: :all, wait: 10)

    state = page.evaluate_script(<<~JS)
      (() => {
        const section = document.querySelector('[aria-labelledby="date-picker-preview-heading"]')
        const card = [...section.querySelectorAll(':scope > div > [data-theme]')]
          .find((el) => el.dataset.theme === 'panel-light')
        const enabled = card.querySelector('input[name$="[stay_date]"]').closest('.panel-date-picker')
        const disabled = card.querySelector('input[name$="[locked_date]"]').closest('.panel-date-picker')
        return {
          enhanced: enabled.dataset.enhanced === 'true',
          enabledTrigger: enabled.querySelector('.panel-date-picker__display').disabled,
          disabledTrigger: disabled.querySelector('.panel-date-picker__display').disabled
        }
      })()
    JS

    expect(state).to eq("enhanced" => true, "enabledTrigger" => false, "disabledTrigger" => true)
  end

  it "opens the calendar in the themed subtree and writes the chosen ISO date back" do
    expect(page).to have_css("#{picker_css('panel-dark', 'stay_date')}[data-panels-ui--date-picker-target='input']", visible: :all, wait: 10)

    result = page.evaluate_script(<<~JS)
      (() => {
        const section = document.querySelector('[aria-labelledby="date-picker-preview-heading"]')
        const card = [...section.querySelectorAll(':scope > div > [data-theme]')]
          .find((el) => el.dataset.theme === 'panel-dark')
        const picker = card.querySelector('input[name$="[stay_date]"]').closest('.panel-date-picker')
        const input = picker.querySelector('input[name$="[stay_date]"]')
        const trigger = picker.querySelector('.panel-date-picker__display')
        const calendar = picker.querySelector("[data-panels-ui--date-picker-target='calendar']")

        trigger.click()
        const opened = picker.querySelector('.popover').matches(':popover-open')
        // The calendar lives inside the themed card — not portalled to <body>.
        const themedHost = calendar.closest('[data-theme]') === card
        const portalled = calendar.closest('.popover').parentElement === document.body

        // Simulate a day selection.
        calendar.value = '2026-07-15'
        calendar.dispatchEvent(new Event('change', { bubbles: true }))

        return {
          opened,
          themedHost,
          portalled,
          inputValue: input.value,
          closedAfter: !picker.querySelector('.popover').matches(':popover-open')
        }
      })()
    JS

    expect(result).to eq(
      "opened" => true,
      "themedHost" => true,
      "portalled" => false,
      "inputValue" => "2026-07-15",
      "closedAfter" => true
    )
  end

  it "renders a seeded value in the trigger display on connect" do
    expect(page).to have_css("#{picker_css('panel-light', 'arrival_date')}", visible: :all, wait: 10)

    text = page.evaluate_script(<<~JS)
      (() => {
        const section = document.querySelector('[aria-labelledby="date-picker-preview-heading"]')
        const card = [...section.querySelectorAll(':scope > div > [data-theme]')]
          .find((el) => el.dataset.theme === 'panel-light')
        return card.querySelector('input[name$="[arrival_date]"]')
          .closest('.panel-date-picker')
          .querySelector('.panel-date-picker__value').textContent
      })()
    JS

    expect(text).to match(/\A\d{4}-\d{2}-\d{2}\z/)
  end

  it "constrains the linked end field's minimum when the start date changes" do
    expect(page).to have_css("#{picker_css('panel-light', 'check_in')}[data-panels-ui--date-picker-target='input']", visible: :all, wait: 10)

    min = page.evaluate_script(<<~JS)
      (() => {
        const section = document.querySelector('[aria-labelledby="date-picker-preview-heading"]')
        const card = [...section.querySelectorAll(':scope > div > [data-theme]')]
          .find((el) => el.dataset.theme === 'panel-light')
        const startCalendar = card.querySelector('input[name$="[check_in]"]')
          .closest('.panel-date-picker')
          .querySelector("[data-panels-ui--date-picker-target='calendar']")
        const endCalendar = card.querySelector('input[name$="[check_out]"]')
          .closest('.panel-date-picker')
          .querySelector("[data-panels-ui--date-picker-target='calendar']")

        startCalendar.value = '2026-07-20'
        startCalendar.dispatchEvent(new Event('change', { bubbles: true }))
        return endCalendar.min
      })()
    JS

    expect(min).to eq("2026-07-20")
  end

  it "clears a linked end field when the start moves beyond it" do
    expect(page).to have_css("#{picker_css('panel-light', 'check_in')}[data-panels-ui--date-picker-target='input']", visible: :all, wait: 10)

    result = page.evaluate_script(<<~JS)
      (() => {
        const section = document.querySelector('[aria-labelledby="date-picker-preview-heading"]')
        const card = [...section.querySelectorAll(':scope > div > [data-theme]')]
          .find((el) => el.dataset.theme === 'panel-light')
        const startCalendar = card.querySelector('input[name$="[check_in]"]')
          .closest('.panel-date-picker').querySelector('calendar-date')
        const endPicker = card.querySelector('input[name$="[check_out]"]').closest('.panel-date-picker')
        const endInput = endPicker.querySelector('input[name$="[check_out]"]')
        const endCalendar = endPicker.querySelector('calendar-date')

        endCalendar.value = '2026-07-20'
        endCalendar.dispatchEvent(new Event('change', { bubbles: true }))
        startCalendar.value = '2026-07-21'
        startCalendar.dispatchEvent(new Event('change', { bubbles: true }))

        return {
          input: endInput.value,
          display: endPicker.querySelector('.panel-date-picker__value').textContent,
          calendar: endCalendar.value
        }
      })()
    JS

    expect(result).to eq("input" => "", "display" => "", "calendar" => "")
  end

  it "removes the linked end minimum when the start is cleared" do
    expect(page).to have_css("#{picker_css('panel-light', 'check_in')}[data-panels-ui--date-picker-target='input']", visible: :all, wait: 10)

    min = page.evaluate_script(<<~JS)
      (() => {
        const section = document.querySelector('[aria-labelledby="date-picker-preview-heading"]')
        const card = [...section.querySelectorAll(':scope > div > [data-theme]')]
          .find((el) => el.dataset.theme === 'panel-light')
        const startCalendar = card.querySelector('input[name$="[check_in]"]')
          .closest('.panel-date-picker').querySelector('calendar-date')
        const endCalendar = card.querySelector('input[name$="[check_out]"]')
          .closest('.panel-date-picker').querySelector('calendar-date')

        startCalendar.value = ''
        startCalendar.dispatchEvent(new Event('change', { bubbles: true }))
        return endCalendar.min
      })()
    JS

    expect(min).to be_blank
  end

  it "keeps the field within a narrow viewport" do
    expect(page).to have_css("#{picker_css('panel-light', 'stay_date')}", visible: :all, wait: 10)

    original_size = page.current_window.size
    page.current_window.resize_to(320, 800)

    geometry = page.evaluate_script(<<~JS)
      (() => {
        const section = document.querySelector('[aria-labelledby="date-picker-preview-heading"]')
        const card = [...section.querySelectorAll(':scope > div > [data-theme]')]
          .find((el) => el.dataset.theme === 'panel-light')
        const field = card.querySelector('input[name$="[stay_date]"]')
          .closest('.panel-form-field').getBoundingClientRect()
        return { fieldRight: Math.ceil(field.right), viewport: document.documentElement.clientWidth }
      })()
    JS

    expect(geometry.fetch("fieldRight")).to be <= geometry.fetch("viewport")
  ensure
    page.current_window.resize_to(*original_size) if original_size
  end

  it "restores the visible range and calendar state when the form resets" do
    expect(page).to have_css("#{picker_css('panel-light', 'report_window')}", visible: :all, wait: 10)

    page.execute_script(<<~JS)
      (() => {
        const input = document.querySelector(#{picker_css('panel-light', 'report_window').to_json})
        const picker = input.closest('.panel-date-picker')
        const calendar = picker.querySelector('calendar-range')
        input.value = '2026-08-01/2026-08-03'
        calendar.value = input.value
        calendar.dispatchEvent(new Event('change', { bubbles: true }))
        input.form.reset()
      })()
    JS
    sleep 0.05

    result = page.evaluate_script(<<~JS)
      (() => {
        const input = document.querySelector(#{picker_css('panel-light', 'report_window').to_json})
        const picker = input.closest('.panel-date-picker')
        const calendar = picker.querySelector('calendar-range')
        return {
          input: input.value,
          calendar: calendar.value,
          display: picker.querySelector('.panel-date-picker__value').textContent
        }
      })()
    JS

    expect(result["input"]).to match(%r{\A\d{4}-\d{2}-\d{2}/\d{4}-\d{2}-\d{2}\z})
    expect(result["calendar"]).to eq(result["input"])
    expect(result["display"]).to include(" to ")
  end

  it "syncs themed caption controls with the calendar focused date" do
    expect(page).to have_css("#{picker_css('panel-light', 'date_of_birth')}", visible: :all, wait: 10)

    result = page.evaluate_script(<<~JS)
      (() => {
        const input = document.querySelector(#{picker_css('panel-light', 'date_of_birth').to_json})
        const picker = input.closest('.panel-date-picker')
        const calendar = picker.querySelector('calendar-date')
        calendar.focusedDate = '1992-03-15'
        calendar.dispatchEvent(new CustomEvent('focusday', { bubbles: true, detail: new Date('1992-03-15T00:00:00Z') }))
        return {
          month: picker.querySelector("[data-panels-ui--date-picker-target='monthLabel']").textContent,
          year: picker.querySelector("[data-panels-ui--date-picker-target='yearLabel']").textContent
        }
      })()
    JS

    expect(result).to eq("month" => "March", "year" => "1992")
  end
end
