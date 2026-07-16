# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::TextArea, type: :component do
  TextAreaObject = Class.new do
    include ActiveModel::Model
    attr_accessor :notes
  end

  def form_for(object = TextAreaObject.new)
    ActionView::Helpers::FormBuilder.new(:profile, object, vc_test_view_context, {})
  end

  it "uses Rails builder content and passes through textarea options" do
    render_inline(
      described_class.new(
        form: form_for(TextAreaObject.new(notes: "<script>alert('x')</script>")),
        attribute: :notes,
        rows: 5,
        maxlength: 500,
        resize: :none,
        described_by: "notes-hint",
        class: "min-h-40",
        data: { controller: "counter" }
      )
    )

    textarea = page.find("textarea#profile_notes")
    expect(textarea[:rows]).to eq("5")
    expect(textarea[:maxlength]).to eq("500")
    expect(textarea[:class]).to include("panel-text-area", "min-h-40")
    expect(textarea["data-resize"]).to eq("none")
    expect(textarea["data-controller"]).to eq("counter")
    expect(textarea["aria-describedby"]).to eq("notes-hint")
    expect(page.native.to_html).to include("&lt;script&gt;alert")
  end

  it "applies invalid and disabled state while defaulting unknown resize values" do
    render_inline(
      described_class.new(
        form: form_for,
        attribute: :notes,
        invalid: true,
        disabled: true,
        readonly: true,
        required: true,
        resize: :unknown
      )
    )

    textarea = page.find("textarea#profile_notes")
    expect(textarea["aria-invalid"]).to eq("true")
    expect(textarea["data-resize"]).to eq("vertical")
    expect(textarea[:required]).to eq("required")
    expect(textarea[:disabled]).to eq("disabled")
    expect(textarea[:readonly]).to eq("readonly")
  end

  it "uses a compact three-row default" do
    render_inline(described_class.new(form: form_for, attribute: :notes))

    expect(page.find("textarea#profile_notes")[:rows]).to eq("3")
  end
end
