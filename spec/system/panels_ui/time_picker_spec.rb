# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PanelsUI::TimePicker", type: :system do
  before { visit "/system-design" }

  def input_css(attribute)
    "[aria-labelledby='time-picker-preview-heading'] [data-theme='panel-light'] input[name$='[#{attribute}]']"
  end

  it "synchronizes keyboard column selection with the hidden value" do
    expect(page).to have_css("#{input_css('check_in_time')}[data-panels-ui--time-picker-target='input']", visible: :all, wait: 10)
    result = page.evaluate_script(<<~JS)
      (() => {
        const input = document.querySelector(#{input_css('check_in_time').to_json})
        const picker = input.closest('.panel-time-picker')
        const control = picker.querySelector('.panel-time-control')
        picker.querySelector('.panel-time-picker__display').click()
        const key = (k) => control.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true }))
        key('ArrowDown'); key('ArrowRight'); key('ArrowDown')
        return { enhanced: picker.dataset.enhanced, value: input.value, active: control.dataset.activePart }
      })()
    JS
    expect(result).to include("enhanced" => "true", "value" => "01:01", "active" => "minutes")
  end

  it "clamps selections to configured bounds" do
    expect(page).to have_css(input_css("office_hours"), visible: :all, wait: 10)
    value = page.evaluate_script(<<~JS)
      (() => {
        const input = document.querySelector(#{input_css('office_hours').to_json})
        const control = input.closest('.panel-time-picker').querySelector('.panel-time-control')
        control.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowUp', bubbles: true }))
        return input.value
      })()
    JS
    expect(value).to eq("17:00")
  end

  it "converts a four-column 12-hour selection to canonical seconds" do
    expect(page).to have_css(input_css("alarm_time"), visible: :all, wait: 10)
    result = page.evaluate_script(<<~JS)
      (() => {
        const input = document.querySelector(#{input_css('alarm_time').to_json})
        const picker = input.closest('.panel-time-picker')
        picker.querySelector('[data-time-option="hours"][data-time-value="10"]').click()
        return { value: input.value, display: picker.querySelector('.panel-time-picker__value').textContent }
      })()
    JS
    expect(result).to eq("value" => "22:30:15", "display" => "10:30:15 PM")
  end

  it "commits split numeric inputs and preserves the last value when invalid" do
    expect(page).to have_css(input_css("checkout_time"), visible: :all, wait: 10)
    result = page.evaluate_script(<<~JS)
      (() => {
        const hidden = document.querySelector(#{input_css('checkout_time').to_json})
        const picker = hidden.closest('.panel-time-picker')
        const hours = picker.querySelector('[data-time-input="hours"]')
        picker.querySelector('.panel-time-picker__display').click()
        hours.focus()
        hours.value = '09'
        hours.dispatchEvent(new Event('input', { bubbles: true }))
        const committed = hidden.value
        hours.value = '99'
        hours.dispatchEvent(new Event('input', { bubbles: true }))
        return {
          committed,
          afterInvalid: hidden.value,
          invalid: hours.getAttribute('aria-invalid'),
          active: picker.querySelector('[data-time-column="hours"]').dataset.active
        }
      })()
    JS

    expect(result).to eq("committed" => "09:00", "afterInvalid" => "09:00", "invalid" => "true", "active" => "true")
  end
end
