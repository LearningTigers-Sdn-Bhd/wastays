# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Autocomplete, type: :component do
  AutocompleteObject = Class.new do
    include ActiveModel::Model
    attr_accessor :name
  end

  def form_for(object = AutocompleteObject.new)
    ActionView::Helpers::FormBuilder.new(:guest, object, vc_test_view_context, {})
  end

  it "renders a free-form input with remote combobox semantics" do
    render_inline(described_class.new(
      form: form_for,
      attribute: :name,
      endpoint: "/guests/search",
      placeholder: "Find a guest"
    ))

    root = page.find(".panel-autocomplete")
    input = page.find("input#guest_name")
    expect(root["data-controller"]).to include("panels-ui--autocomplete")
    expect(root["data-panels-ui--autocomplete-endpoint-value"]).to eq("/guests/search")
    expect(input["role"]).to eq("combobox")
    expect(input["aria-autocomplete"]).to eq("list")
    expect(input["aria-expanded"]).to eq("false")
    expect(input["aria-controls"]).to eq("guest_name-autocomplete-listbox")
    expect(input["autocomplete"]).to eq("off")
    expect(page).to have_css("#guest_name-autocomplete-listbox[role='listbox'][hidden]", visible: :all)
  end

  it "propagates field state and custom root data" do
    render_inline(described_class.new(
      form: form_for,
      attribute: :name,
      endpoint: "/guests/search",
      described_by: "name-error",
      required: true,
      disabled: true,
      invalid: true,
      size: :lg,
      data: { testid: "guest-search" }
    ))

    root = page.find(".panel-autocomplete")
    input = page.find("input", visible: :all)
    expect(root["data-size"]).to eq("lg")
    expect(root["data-invalid"]).to eq("true")
    expect(root["data-testid"]).to eq("guest-search")
    expect(input["required"]).to eq("required")
    expect(input["disabled"]).to eq("disabled")
    expect(input["aria-invalid"]).to eq("true")
    expect(input["aria-describedby"]).to eq("name-error")
  end

  it "is available through FormField#with_autocomplete" do
    render_inline(PanelsUI::FormField.new(form: form_for, attribute: :name, label: "Guest")) do |field|
      field.with_autocomplete(endpoint: "/guests/search")
    end

    expect(page).to have_css("label[for='guest_name']", text: "Guest")
    expect(page).to have_css(".panel-autocomplete input#guest_name")
  end

  it "requires an endpoint" do
    expect {
      described_class.new(form: form_for, attribute: :name, endpoint: nil)
    }.to raise_error(ArgumentError, /require an endpoint/)
  end
end
