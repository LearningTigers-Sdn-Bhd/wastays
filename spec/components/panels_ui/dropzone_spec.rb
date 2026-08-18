# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Dropzone, type: :component do
  DropzoneObject = Class.new do
    include ActiveModel::Model
    attr_accessor :photos, :icon, :remove_icon
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

  it "renders a persisted single image with replace, staged removal, and an accessible native input" do
    render_inline(
      described_class.new(
        form: form_for,
        attribute: :icon,
        accept: "image/png,image/jpeg,image/webp",
        max_size: 2.megabytes,
        preview: :image,
        presentation: :single_image,
        existing_image_url: "/hotel-icon.png",
        existing_image_alt: "Seaside Hotel icon",
        remove_attribute: :remove_icon,
        labelled_by: "icon-label"
      )
    )

    expect(page).to have_css(".panel-dropzone[data-panels-ui--dropzone-presentation-value='single_image']")
    expect(page).to have_css("input#room_icon[type='file'][accept='image/png,image/jpeg,image/webp']", visible: :all)
    expect(page).to have_css("input#room_remove_icon[type='hidden'][name='room[remove_icon]'][value='0']", visible: :all)
    expect(page).to have_css(".panel-dropzone__single-image img[src='/hotel-icon.png'][alt='Seaside Hotel icon']")
    expect(page).to have_button("Replace")
    expect(page).to have_button("Remove")
    expect(page).to have_button("Undo remove", visible: :all)
    expect(page).to have_no_css(".panel-dropzone__selection")
  end

  it "rejects a multiple-file single-image presentation" do
    expect do
      render_inline(described_class.new(form: form_for, attribute: :icon, multiple: true, presentation: :single_image))
    end.to raise_error(ArgumentError, "Single-image dropzones do not support multiple files")
  end
end
