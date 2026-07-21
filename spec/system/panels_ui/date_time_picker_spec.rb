# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PanelsUI::DateTimePicker", type: :system do
  before { visit_when_loaded "/system-design?only=date_time_picker_preview" }

  def input_css(attribute)
    "[aria-labelledby='date-time-picker-preview-heading'] [data-theme='panel-light'] input[name$='[#{attribute}]']"
  end

  it "combines a calendar date with its child time control" do
    expect(page).to have_css(input_css("arrives_at"), visible: :all, wait: 10)
    result = page.evaluate_script(<<~JS)
      (() => {
        const input = document.querySelector(#{input_css('arrives_at').to_json})
        const picker = input.closest('.panel-date-time-picker')
        const calendar = picker.querySelector('calendar-date')
        calendar.value = '2026-07-15'; calendar.dispatchEvent(new Event('change', { bubbles: true }))
        const control = picker.querySelector('.panel-time-control')
        control.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true }))
        control.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true }))
        return { value: input.value, display: picker.querySelector('.panel-date-time-picker__value').textContent }
      })()
    JS
    expect(result["value"]).to eq("2026-07-15T00:01")
    expect(result["display"]).to include("2026-07-15 00:01")
  end

  it "keeps the calendar open while its child opens and closes the child first on Escape" do
    expect(page).to have_css(input_css("departs_at"), visible: :all, wait: 10)
    input = find(input_css("departs_at"), visible: :all)
    picker = input.find(:xpath, "ancestor::*[contains(@class,'panel-date-time-picker')]", visible: :all)
    picker.find(".panel-date-time-picker__display").click
    expect(picker).to have_css(".panel-date-time-picker__popover:popover-open")
    time_trigger = picker.find(".panel-date-time-picker__time-trigger")
    time_trigger.click
    expect(picker).to have_css(".panel-date-time-picker__time-popover:popover-open")
    expect(picker).to have_css(".panel-date-time-picker__popover:popover-open")
    page.send_keys(:escape)
    expect(picker).to have_no_css(".panel-date-time-picker__time-popover:popover-open")
    expect(picker).to have_css(".panel-date-time-picker__popover:popover-open")
    expect(page).to have_css("##{time_trigger[:id]}:focus", wait: 2)
  end

  it "keeps separate start and end values in a datetime range" do
    expect(page).to have_css(input_css("stay_window"), visible: :all, wait: 10)
    value = page.evaluate_script(<<~JS)
      (() => {
        const input = document.querySelector(#{input_css('stay_window').to_json})
        const picker = input.closest('.panel-date-time-picker')
        const calendar = picker.querySelector('calendar-range')
        calendar.value = '2026-08-10/2026-08-12'; calendar.dispatchEvent(new Event('change', { bubbles: true }))
        const end = picker.querySelector('[data-panels-ui--date-time-picker-target="endTimeControl"]')
        end.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true }))
        end.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true }))
        return input.value
      })()
    JS
    expect(value).to match(%r{\A2026-08-10T\d{2}:\d{2}/2026-08-12T\d{2}:\d{2}\z})
  end
end
