# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Dropzone, type: :component do
  DropzoneObject = Class.new do
    include ActiveModel::Model
    attr_accessor :photos
  end

  def form_for(object = DropzoneObject.new)
    ActionView::Helpers::FormBuilder.new(:room, object, vc_test_view_context, {})
  end

  it "renders a progressively enhanced native file input and attachment template" do
    render_inline(
      described_class.new(
        form: form_for,
        attribute: :photos,
        accept: "image/*",
        multiple: true,
        max_files: 5,
        max_size: 2.megabytes,
        existing_count: 1,
        description: "PNG or JPEG, up to 2 MB each.",
        labelled_by: "photos-label",
        described_by: "photos-hint"
      )
    )

    root = page.find(".panel-dropzone")
    expect(root["data-controller"]).to eq("panels-ui--dropzone")
    expect(root["data-panels-ui--dropzone-max-files-value"]).to eq("5")
    expect(root["data-panels-ui--dropzone-max-size-value"]).to eq(2.megabytes.to_s)
    expect(root["aria-labelledby"]).to eq("photos-label")

    input = page.find("input#room_photos[type='file']", visible: :all)
    expect(input[:name]).to eq("room[photos][]")
    expect(input[:accept]).to eq("image/*")
    expect(input[:multiple]).to eq("multiple")
    expect(input["aria-describedby"]).to eq("photos-hint room_photos-dropzone-error")
    expect(page).to have_css("label.panel-dropzone__browse[for='room_photos']", text: "Browse")
    expect(page).to have_css("template[data-panels-ui--dropzone-target='template']", visible: :all)
    expect(page.native.to_html).to include("panel-attachment")
    expect(page).to have_css("#room_photos-dropzone-error[role='alert'][aria-live='polite']", visible: :all)
  end

  it "uses a single-file limit and propagates invalid, required, and disabled states" do
    render_inline(
      described_class.new(
        form: form_for,
        attribute: :photos,
        required: true,
        disabled: true,
        invalid: true,
        preview: :unknown
      )
    )

    expect(page).to have_css(".panel-dropzone[data-invalid='true'][data-disabled='true']")
    expect(page).to have_css("input[type='file'][required][disabled][aria-invalid='true']", visible: :all)
    expect(page).to have_css(".panel-attachment-group[data-layout='list']", visible: :all)
  end

  it "validates numeric limits" do
    expect do
      render_inline(described_class.new(form: form_for, attribute: :photos, multiple: true, max_files: 0))
    end.to raise_error(ArgumentError, "max_files must be greater than zero")

    expect do
      render_inline(described_class.new(form: form_for, attribute: :photos, max_size: -1))
    end.to raise_error(ArgumentError, "max_size must not be negative")
  end
end
