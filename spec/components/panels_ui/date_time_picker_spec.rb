# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::DateTimePicker, type: :component do
  DateTimePickerObject = Class.new do
    include ActiveModel::Model
    attr_accessor :arrives_at
  end

  def form_for(object = DateTimePickerObject.new)
    ActionView::Helpers::FormBuilder.new(:booking, object, vc_test_view_context, {})
  end

  it "renders a hidden field with a calendar + segmented time popover" do
    render_inline(described_class.new(form: form_for, attribute: :arrives_at))

    root = page.find(".panel-date-time-picker")
    expect(root["data-controller"]).to include("panels-ui--date-time-picker")
    expect(root["data-size"]).to eq("md")

    expect(page).to have_css("input#booking_arrives_at[type='hidden'][data-panels-ui--date-time-picker-target='input']", visible: :all)
    expect(page).to have_css("button.panel-input.panel-date-time-picker__display[data-panels-ui--date-time-picker-target='trigger']")
    expect(page).to have_css("calendar-date[data-panels-ui--date-time-picker-target='calendar'] calendar-month")
    expect(page).to have_css("button.panel-date-time-picker__time-trigger", text: "Time")
    expect(page).to have_css(".panel-time-control[data-panels-ui--date-time-picker-target='timeControl']")
    expect(page).to have_css(".panel-date-time-picker__time-popover[data-panels-ui--popover-target='panel']")
  end

  it "wires the popover outlet to the nested popover root" do
    render_inline(described_class.new(form: form_for, attribute: :arrives_at))

    selector = page.find(".panel-date-time-picker")["data-panels-ui--date-time-picker-panels-ui--popover-outlet"]
    expect(selector).to eq(".booking_arrives_at-date-time-picker__popover")
    expect(page).to have_css(".popover-root#{selector}[data-controller~='panels-ui--popover']")
  end

  it "passes date-only bounds to the calendar and keeps step as a data-value" do
    render_inline(described_class.new(
      form: form_for, attribute: :arrives_at, min: "2026-07-12T09:00", max: "2026-12-31T17:00", step: 15
    ))

    root = page.find(".panel-date-time-picker")
    expect(root["data-panels-ui--date-time-picker-min-value"]).to eq("2026-07-12T09:00")
    expect(root["data-panels-ui--date-time-picker-max-value"]).to eq("2026-12-31T17:00")
    expect(root["data-panels-ui--date-time-picker-step-value"]).to eq("15")
    expect(page).to have_css("calendar-date[min='2026-07-12'][max='2026-12-31']")
  end

  it "renders a two-month datetime range with separate start and end time segments" do
    render_inline(described_class.new(
      form: form_for, attribute: :arrives_at, range: true, months: 2,
      value: "2026-07-12T14:00/2026-07-15T11:00"
    ))

    root = page.find(".panel-date-time-picker")
    expect(root["data-panels-ui--date-time-picker-mode-value"]).to eq("range")
    expect(page).to have_css("calendar-range[months='2'] calendar-month[offset='1']")
    expect(page).to have_css("[data-panels-ui--date-time-picker-target='startTimeControl']")
    expect(page).to have_css("[data-panels-ui--date-time-picker-target='endTimeControl']")
    expect(page).to have_css(".panel-date-time-picker__time-trigger", count: 2)
    expect(page).to have_css("input[value='2026-07-12T14:00/2026-07-15T11:00']", visible: :all)
  end

  it "renders 12-hour seconds controls and preserves second-precision values" do
    render_inline(described_class.new(
      form: form_for, attribute: :arrives_at, hour_cycle: 12, precision: :seconds,
      second_step: 15, value: "2026-07-12T21:30:15"
    ))

    root = page.find(".panel-date-time-picker")
    expect(root["data-panels-ui--date-time-picker-hour-cycle-value"]).to eq("12")
    expect(root["data-panels-ui--date-time-picker-precision-value"]).to eq("seconds")
    expect(page).to have_css("input[value='2026-07-12T21:30:15']", visible: :all)
    expect(page).to have_css("[role='listbox']", count: 4)
  end

  it "reflects disabled/readonly on the root and disables the trigger" do
    render_inline(described_class.new(form: form_for, attribute: :arrives_at, disabled: true, readonly: true))

    root = page.find(".panel-date-time-picker")
    expect(root["data-disabled"]).to eq("true")
    expect(root["data-readonly"]).to eq("true")
    expect(page).to have_css("button.panel-date-time-picker__display[disabled]")
  end
end
