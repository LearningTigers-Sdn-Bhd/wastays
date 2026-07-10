# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Input, type: :component do
  InputObject = Class.new do
    include ActiveModel::Model
    attr_accessor :email, :amount
  end

  def form_for(object = InputObject.new)
    ActionView::Helpers::FormBuilder.new(:profile, object, vc_test_view_context, {})
  end

  it "uses Rails builder helpers while passing through HTML, data, and ARIA attributes" do
    render_inline(
      described_class.new(
        form: form_for,
        attribute: :email,
        type: :email,
        described_by: "email-hint",
        placeholder: "guest@example.com",
        class: "w-full",
        data: { controller: "email-check" },
        aria: { label: "Contact email", describedby: "external-description" }
      )
    )

    input = page.find("input#profile_email")
    expect(input[:type]).to eq("email")
    expect(input[:placeholder]).to eq("guest@example.com")
    expect(input[:class]).to include("panel-input", "w-full")
    expect(input["data-controller"]).to eq("email-check")
    expect(input["aria-label"]).to eq("Contact email")
    expect(input["aria-describedby"]).to eq("external-description email-hint")
  end

  it "renders field states and safely falls back to a text field" do
    render_inline(
      described_class.new(
        form: form_for,
        attribute: :amount,
        type: :unknown,
        size: :bogus,
        invalid: true,
        required: true,
        disabled: true,
        readonly: true
      )
    )

    input = page.find("input#profile_amount")
    expect(input[:type]).to eq("text")
    expect(input["data-size"]).to eq("md")
    expect(input["aria-invalid"]).to eq("true")
    expect(input[:required]).to eq("required")
    expect(input[:disabled]).to eq("disabled")
    expect(input[:readonly]).to eq("readonly")
  end
end
