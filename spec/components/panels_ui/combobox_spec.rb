# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Combobox, type: :component do
  ComboboxObject = Class.new do
    include ActiveModel::Model
    attr_accessor :destination
  end

  def form_for(object = ComboboxObject.new)
    ActionView::Helpers::FormBuilder.new(:profile, object, vc_test_view_context, {})
  end

  let(:choices) do
    [
      { label: "Bangkok", value: "bangkok" },
      { label: "Berlin", value: "berlin" },
      { label: "Kuching", value: "kuching", disabled: true }
    ]
  end

  it "accepts a mixture of label/value pairs and rich hash choices" do
    mixed_choices = [ [ "Bangkok", "bangkok" ], { label: "Kuching", value: "kuching", disabled: true } ]

    render_inline(described_class.new(
      form: form_for,
      attribute: :destination,
      choices: mixed_choices
    ))

    expect(page).to have_css("option[value='bangkok']", text: "Bangkok")
    expect(page).to have_css("option[value='kuching'][disabled]", text: "Kuching")
  end

  it "renders an enhanced native select as the source of truth" do
    render_inline(described_class.new(
      form: form_for,
      attribute: :destination,
      choices: choices,
      prompt: "Search destinations"
    ))

    root = page.find(".panel-combobox")
    expect(root["data-controller"]).to include("panels-ui--combobox")
    expect(root["data-panels-ui--combobox-placeholder-value"]).to eq("Search destinations")
    expect(root["data-size"]).to eq("md")

    expect(page).to have_css("select#profile_destination.panel-native-select.panel-combobox__native")
    expect(page).to have_css("select[data-panels-ui--combobox-target='native']")
    expect(page.find("select")["data-action"]).to include("change->panels-ui--combobox#syncFromNative")
  end

  it "preserves selection and disabled choices in the native select" do
    render_inline(described_class.new(
      form: form_for,
      attribute: :destination,
      choices: choices,
      selected: "berlin"
    ))

    expect(page).to have_css("option[value='berlin'][selected]", text: "Berlin")
    expect(page).to have_css("option[value='kuching'][disabled]", text: "Kuching")
  end

  it "propagates field state, descriptions, size, and root attributes" do
    render_inline(described_class.new(
      form: form_for,
      attribute: :destination,
      choices: choices,
      described_by: "destination-error",
      required: true,
      disabled: true,
      invalid: true,
      size: :lg,
      class: "max-w-md",
      data: { testid: "destination-combobox" }
    ))

    root = page.find(".panel-combobox.max-w-md")
    expect(root["data-size"]).to eq("lg")
    expect(root["data-invalid"]).to eq("true")
    expect(root["data-disabled"]).to eq("true")
    expect(root["data-testid"]).to eq("destination-combobox")
    expect(page).to have_css("select[required][disabled][aria-invalid='true'][aria-describedby='destination-error']")
  end

  it "is available through FormField#with_combobox" do
    render_inline(PanelsUI::FormField.new(
      form: form_for,
      attribute: :destination,
      label: "Destination",
      hint: "Search available destinations."
    )) do |field|
      field.with_combobox(choices, prompt: "Search destinations")
    end

    expect(page).to have_css("label[for='profile_destination']", text: "Destination")
    expect(page).to have_css(".panel-combobox select[aria-describedby='profile_destination-hint']")
  end

  it "raises without choices" do
    expect {
      described_class.new(form: form_for, attribute: :destination, choices: [])
    }.to raise_error(ArgumentError, /require choices/)
  end
end
