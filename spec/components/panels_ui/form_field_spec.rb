# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::FormField, type: :component do
  FormFieldObject = Class.new do
    include ActiveModel::Model
    attr_accessor :email, :notes, :nightly_rate, :reference, :files
  end

  def form_for(object = FormFieldObject.new)
    ActionView::Helpers::FormBuilder.new(:profile, object, vc_test_view_context, {})
  end

  def render_field(object: FormFieldObject.new, **options, &block)
    render_inline(described_class.new(form: form_for(object), attribute: :email, **options), &block)
  end

  it "composes a Cally date picker control wired to the field id and description" do
    render_field(label: "Check-in", hint: "Standard check-in is 3 PM.") do |field|
      field.with_date_picker
    end

    expect(page).to have_css("label.panel-form-field__label[for='profile_email']", text: "Check-in")
    root = page.find(".panel-date-picker")
    expect(root["data-controller"]).to include("panels-ui--date-picker")
    expect(page).to have_css("calendar-date[data-panels-ui--date-picker-target='calendar']")
    expect(page).to have_css("input#profile_email[type='hidden']", visible: :all)
    expect(page).to have_css("button.panel-date-picker__display[aria-describedby='profile_email-hint']")
  end

  it "composes time and datetime picker controls wired to the field id" do
    render_field(label: "Check-in time") { |field| field.with_time_picker }
    expect(page).to have_css(".panel-time-picker[data-controller~='panels-ui--time-picker']")
    expect(page).to have_css("input#profile_email[type='hidden']", visible: :all)
    expect(page).to have_css("button.panel-time-picker__display")

    render_field(label: "Arrival") { |field| field.with_date_time_picker }
    expect(page).to have_css(".panel-date-time-picker[data-controller~='panels-ui--date-time-picker']")
    expect(page).to have_css("input#profile_email[type='hidden']", visible: :all)
    expect(page).to have_css("button.panel-date-time-picker__display")
  end

  it "composes an input with a linked label and hint" do
    render_field(label: "Email address", hint: "Used for booking notifications.") do |field|
      field.with_input(type: :email, placeholder: "guest@example.com")
    end

    expect(page).to have_css(".panel-form-field[data-size='md'][data-invalid='false']")
    expect(page).to have_css("label.panel-form-field__label[for='profile_email']", text: "Email address")
    expect(page).to have_css("input#profile_email.panel-input[type='email'][aria-describedby='profile_email-hint']")
    expect(page).to have_css("#profile_email-hint.panel-form-field__hint", text: "Used for booking notifications.")
  end

  it "derives errors from the builder object and wires the invalid description" do
    object = FormFieldObject.new
    object.errors.add(:email, "is already in use")

    render_field(object: object, label: "Email") { |field| field.with_input(type: :email) }

    expect(page).to have_css(".panel-form-field[data-invalid='true']")
    expect(page).to have_css("input[aria-invalid='true'][aria-describedby='profile_email-error']")
    expect(page).to have_css("#profile_email-error.panel-form-field__error[role='alert']", text: "is already in use")
    expect(page).to have_no_css("#profile_email-hint")
  end

  it "propagates required, disabled, readonly, and hidden-label state to the control" do
    render_field(label: "Email", required: true, disabled: true, readonly: true, label_hidden: true) do |field|
      field.with_input
    end

    expect(page).to have_css("label.sr-only", text: "Email")
    expect(page).to have_css("input[required][disabled][readonly]")
    expect(page).to have_css("span.sr-only", text: "(required)", visible: :all)
  end

  it "overrides the generated control id, and the ids derived from it, when given one" do
    object = FormFieldObject.new
    object.errors.add(:email, "is already in use")

    render_field(object: object, id: "row-7-email", label: "Email") { |field| field.with_input }

    expect(page).to have_css("label.panel-form-field__label[for='row-7-email']", text: "Email")
    expect(page).to have_css("input#row-7-email[aria-describedby='row-7-email-error']")
    expect(page).to have_css("#row-7-email-error.panel-form-field__error", text: "is already in use")
    expect(page).to have_no_css("#profile_email")
  end

  it "propagates the selected size through every typed control" do
    controls = {
      input: ".panel-input[data-size='sm']",
      date_picker: ".panel-date-picker[data-size='sm']",
      time_picker: ".panel-time-picker[data-size='sm']",
      date_time_picker: ".panel-date-time-picker[data-size='sm']",
      dropzone: ".panel-dropzone[data-size='sm']",
      text_area: ".panel-text-area[data-size='sm']",
      native_select: ".panel-native-select[data-size='sm']",
      select_menu: ".panel-select-menu[data-size='sm']",
      combobox: ".panel-combobox[data-size='sm']",
      multi_select: ".panel-multi-select[data-size='sm']"
    }

    controls.each do |kind, selector|
      render_field(size: :sm) do |field|
        choices = [ [ "One", "1" ] ] if %i[native_select select_menu combobox multi_select].include?(kind)
        choices ? field.public_send("with_#{kind}", choices) : field.public_send("with_#{kind}")
      end
      expect(page).to have_css(selector)
    end
  end

  # The field's own size used to be splatted over whatever the control asked for,
  # so a caller sizing the control against its container — a field in a table
  # cell — was silently rendered at the field's size instead.
  it "lets a control keep the size it was given rather than the field's" do
    render_field(size: :md) do |field|
      field.with_input(size: :sm)
    end

    expect(page).to have_css(".panel-form-field[data-size='md'] .panel-input[data-size='sm']")
  end

  it "creates an inline control group for start and end addons after the input in the DOM" do
    render_field(label: "Rate") do |field|
      field.with_input(type: :number)
      field.with_addon(align: :inline_start) { "MYR" }
      field.with_addon(align: :inline_end) { "per night" }
    end

    group = page.find(".panel-control-group[data-layout='inline']")
    expect(group).to have_css("input.panel-input")
    expect(group).to have_css(".panel-control-group__addon[data-align='inline-start'][data-variant='bordered']", text: "MYR")
    expect(group).to have_css(".panel-control-group__addon[data-align='inline-end'][data-variant='bordered']", text: "per night")
    expect(group.native.to_html.index("panel-input")).to be < group.native.to_html.index("inline-start")
  end

  it "supports bare addons and falls back unknown variants to bordered" do
    render_field(label: "Email") do |field|
      field.with_input
      field.with_addon(align: :inline_start, variant: :bare) { "Bare" }
      field.with_addon(align: :inline_end, variant: :unknown) { "Fallback" }
    end

    expect(page).to have_css("[data-align='inline-start'][data-variant='bare']", text: "Bare")
    expect(page).to have_css("[data-align='inline-end'][data-variant='bordered']", text: "Fallback")
  end

  it "creates a block control group for textarea addons" do
    render_field(label: "Notes") do |field|
      field.with_text_area(rows: 4)
      field.with_addon(align: :block_start) { "Staff only" }
      field.with_addon(align: :block_end) { "0 / 500" }
    end

    expect(page).to have_css(".panel-control-group[data-layout='block'] textarea.panel-text-area[rows='4']")
    expect(page).to have_css(".panel-control-group__addon[data-align='block-start']", text: "Staff only")
    expect(page).to have_css(".panel-control-group__addon[data-align='block-end']", text: "0 / 500")
  end

  it "rejects addon directions that do not match the control" do
    expect do
      render_field(label: "Notes") do |field|
        field.with_text_area
        field.with_addon(align: :inline_start) { "Invalid" }
      end
    end.to raise_error(ArgumentError, "Text areas only support block_start, block_end addons")
  end

  it "requires a typed control slot" do
    expect { render_field(label: "Email") }.to raise_error(ArgumentError, "Form fields require a control")
  end

  it "composes a dropzone with field-owned label, hint, and state" do
    render_inline(
      described_class.new(
        form: form_for,
        attribute: :files,
        label: "Room photos",
        hint: "Add up to five photos.",
        required: true
      )
    ) do |field|
      field.with_dropzone(accept: "image/*", multiple: true, max_files: 5)
    end

    expect(page).to have_css("label#profile_files-label[for='profile_files']", text: "Room photos")
    expect(page).to have_css(".panel-dropzone[aria-labelledby='profile_files-label']")
    expect(page).to have_css("input#profile_files[type='file'][required][aria-describedby~='profile_files-hint']", visible: :all)
    expect(page).to have_css("#profile_files-hint", text: "Add up to five photos.")
  end

  it "does not allow control-group addons on a dropzone" do
    expect do
      render_field(label: "Files") do |field|
        field.with_dropzone
        field.with_addon(align: :block_end) { "Unsupported" }
      end
    end.to raise_error(ArgumentError, "Dropzones do not support addons")
  end
end
