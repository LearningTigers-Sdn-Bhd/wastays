# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::DatePicker, type: :component do
  DatePickerObject = Class.new do
    include ActiveModel::Model
    attr_accessor :check_in, :check_out, :arrives_at, :window
  end

  def form_for(object = DatePickerObject.new)
    ActionView::Helpers::FormBuilder.new(:booking, object, vc_test_view_context, {})
  end

  it "renders a hidden ISO field as the source of truth, with a Cally calendar popover" do
    render_inline(described_class.new(form: form_for, attribute: :check_in))

    root = page.find(".panel-date-picker")
    expect(root["data-controller"]).to include("panels-ui--date-picker")
    expect(root["data-panels-ui--date-picker-mode-value"]).to eq("single")
    expect(root["data-size"]).to eq("md")

    # Hidden field is the form source of truth; the visible field is a button trigger.
    expect(page).to have_css("input#booking_check_in[type='hidden'][data-panels-ui--date-picker-target='input']", visible: :all)
    expect(page).to have_css("button.panel-input.panel-date-picker__display[data-panels-ui--date-picker-target='trigger']")
    expect(page).to have_css(".panel-date-picker__value[data-placeholder='Select a date']")
    # The nested Popover shell + a Cally single-date calendar.
    expect(page).to have_css(".panel-date-picker .popover-root")
    expect(page).to have_css("calendar-date[data-panels-ui--date-picker-target='calendar'] calendar-month")
  end

  it "wires the popover outlet to the nested popover root" do
    render_inline(described_class.new(form: form_for, attribute: :check_in))

    root = page.find(".panel-date-picker")
    selector = root["data-panels-ui--date-picker-panels-ui--popover-outlet"]
    expect(selector).to eq(".booking_check_in-date-picker__popover")
    expect(page).to have_css(".popover-root#{selector}[data-controller~='panels-ui--popover']")
  end

  it "applies the requested size to the visible trigger" do
    render_inline(described_class.new(form: form_for, attribute: :check_in, size: :sm))

    expect(page).to have_css("button.panel-date-picker__display[data-size='sm']")
  end

  it "renders a range calendar and range placeholder for a single-input range" do
    render_inline(described_class.new(form: form_for, attribute: :window, range: true))

    expect(page.find(".panel-date-picker")["data-panels-ui--date-picker-mode-value"]).to eq("range")
    expect(page).to have_css("input#booking_window[type='hidden']", visible: :all)
    expect(page).to have_css(".panel-date-picker__value[data-placeholder='Select a range']")
    expect(page).to have_css("calendar-range[data-panels-ui--date-picker-target='calendar']")
  end

  it "renders an adjacent two-month range and themed dropdown caption controls" do
    render_inline(described_class.new(
      form: form_for, attribute: :window, range: true, months: 2,
      caption_layout: :dropdown, year_range: 2020..2026
    ))

    expect(page).to have_css("calendar-range[months='2'] calendar-month[offset='1']")
    expect(page).to have_css(".panel-calendar-caption__trigger[aria-label='Choose month']")
    expect(page).to have_css("[role='listbox'][aria-label='Choose year'] [role='option']", count: 7, visible: :all)
  end

  it "exposes responsive two-month range configuration" do
    render_inline(described_class.new(
      form: form_for,
      attribute: :window,
      range: true,
      months: 2,
      responsive_months: true,
      value: "2026-07-01/2026-07-31"
    ))

    root = page.find(".panel-date-picker")
    expect(root["data-panels-ui--date-picker-months-value"]).to eq("2")
    expect(root["data-panels-ui--date-picker-responsive-months-value"]).to eq("true")
    expect(page).to have_css("input[value='2026-07-01/2026-07-31']", visible: :all)
  end

  it "exposes validation and label relationships on the visible trigger" do
    render_inline(described_class.new(
      form: form_for, attribute: :window, labelled_by: "booking_window-label",
      described_by: "booking_window-error", required: true, invalid: true
    ))

    expect(page).to have_css(
      "button.panel-date-picker__display[aria-labelledby='booking_window-label']" \
      "[aria-describedby='booking_window-error'][aria-required='true'][aria-invalid='true']"
    )
  end

  it "emits the linked field id for a linked two-field range" do
    render_inline(described_class.new(form: form_for, attribute: :check_in, range: true, linked_to: :check_out))

    root = page.find(".panel-date-picker")
    # A linked range still runs each field in single mode.
    expect(root["data-panels-ui--date-picker-mode-value"]).to eq("single")
    expect(root["data-panels-ui--date-picker-linked-to-value"]).to eq("booking_check_out")
    expect(page).to have_css("input#booking_check_in[type='hidden']", visible: :all)
    expect(page).to have_css("calendar-date[data-panels-ui--date-picker-target='calendar']")
  end

  it "serializes Date/Time bounds to ISO-8601 and passes strings through" do
    render_inline(described_class.new(
      form: form_for, attribute: :check_in, min: Date.new(2026, 7, 12), max: "2026-12-31"
    ))

    root = page.find(".panel-date-picker")
    expect(root["data-panels-ui--date-picker-min-value"]).to eq("2026-07-12")
    expect(root["data-panels-ui--date-picker-max-value"]).to eq("2026-12-31")
  end

  it "seeds the hidden field with an initial value" do
    render_inline(described_class.new(form: form_for, attribute: :check_in, value: "2026-07-15"))

    expect(page).to have_css("input#booking_check_in[type='hidden'][value='2026-07-15']", visible: :all)
  end

  it "omits optional bound and linked-to attributes when not provided" do
    render_inline(described_class.new(form: form_for, attribute: :check_in))

    root = page.find(".panel-date-picker")
    expect(root["data-panels-ui--date-picker-min-value"]).to be_nil
    expect(root["data-panels-ui--date-picker-linked-to-value"]).to be_nil
  end

  it "reflects disabled/readonly on the root and disables the trigger so it cannot open" do
    render_inline(described_class.new(form: form_for, attribute: :check_in, disabled: true, readonly: true))

    root = page.find(".panel-date-picker")
    expect(root["data-disabled"]).to eq("true")
    expect(root["data-readonly"]).to eq("true")
    expect(page).to have_css("button.panel-date-picker__display[disabled]")
  end
end
