# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::TimePicker, type: :component do
  TimePickerObject = Class.new do
    include ActiveModel::Model
    attr_accessor :check_in_time
  end

  def form_for(object = TimePickerObject.new)
    ActionView::Helpers::FormBuilder.new(:booking, object, vc_test_view_context, {})
  end

  it "renders a hidden field with direct entry and scrollable columns" do
    render_inline(described_class.new(form: form_for, attribute: :check_in_time))

    root = page.find(".panel-time-picker")
    expect(root["data-controller"]).to include("panels-ui--time-picker")
    expect(root["data-size"]).to eq("md")

    expect(page).to have_css("input#booking_check_in_time[type='hidden'][data-panels-ui--time-picker-target='input']", visible: :all)
    expect(page).to have_css("button.panel-input.panel-time-picker__display[data-panels-ui--time-picker-target='trigger']")
    expect(page).to have_css(".panel-time-picker__value[data-placeholder='Select a time']")
    expect(page).to have_css(".panel-time-control[data-panels-ui--time-picker-target='timeControl']")
    expect(page).to have_css(".panel-time-control[tabindex='-1'] > .panel-time-control__columns")
    expect(page).to have_css("input.panel-time-control__input[data-time-input='hours'][inputmode='numeric'][maxlength='2']")
    expect(page).to have_css("input.panel-time-control__input[data-time-input='minutes'][inputmode='numeric'][maxlength='2']")
    expect(page).to have_css("[role='listbox'][aria-label='Minutes']")
    expect(page).to have_css(".panel-scroll-area__viewport[tabindex='-1']", count: 2)
    expect(page).to have_css(".panel-time-control__column[data-time-kind='numeric']", count: 2)
  end

  it "wires the popover outlet to the nested popover root" do
    render_inline(described_class.new(form: form_for, attribute: :check_in_time))

    selector = page.find(".panel-time-picker")["data-panels-ui--time-picker-panels-ui--popover-outlet"]
    expect(selector).to eq(".booking_check_in_time-time-picker__popover")
    expect(page).to have_css(".popover-root#{selector}[data-controller~='panels-ui--popover']")
  end

  it "emits min/max/step as data-values for the segments" do
    render_inline(described_class.new(
      form: form_for, attribute: :check_in_time, min: "09:00", max: "17:00", step: 15
    ))

    root = page.find(".panel-time-picker")
    expect(root["data-panels-ui--time-picker-min-value"]).to eq("09:00")
    expect(root["data-panels-ui--time-picker-max-value"]).to eq("17:00")
    expect(root["data-panels-ui--time-picker-step-value"]).to eq("15")
    expect(root["data-panels-ui--time-picker-minute-step-value"]).to eq("15")
  end

  it "renders four columns for a 12-hour seconds picker" do
    render_inline(described_class.new(form: form_for, attribute: :check_in_time, hour_cycle: 12, precision: :seconds, second_step: 15))

    root = page.find(".panel-time-picker")
    expect(root["data-panels-ui--time-picker-hour-cycle-value"]).to eq("12")
    expect(root["data-panels-ui--time-picker-precision-value"]).to eq("seconds")
    expect(page).to have_css("[role='listbox']", count: 4)
    expect(page).to have_css("[role='listbox'][aria-label='AM/PM'] [role='option']", count: 2)
    expect(page).to have_css("[role='listbox'][aria-label='Seconds'] [role='option']", count: 4)
    expect(page).to have_css("input[data-time-input='period'][disabled][tabindex='-1']")
    expect(page).to have_css(".panel-time-control__column[data-time-kind='period']", count: 1)
  end

  it "reflects disabled/readonly on the root and disables the trigger" do
    render_inline(described_class.new(form: form_for, attribute: :check_in_time, disabled: true, readonly: true))

    root = page.find(".panel-time-picker")
    expect(root["data-disabled"]).to eq("true")
    expect(root["data-readonly"]).to eq("true")
    expect(page).to have_css("button.panel-time-picker__display[disabled]")
  end
end
