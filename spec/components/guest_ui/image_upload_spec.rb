# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::ImageUpload, type: :component do
  def render_upload(**options)
    form = ActionView::Helpers::FormBuilder.new(:booking, nil, vc_test_view_context, {})
    render_inline(described_class.new(form: form, attribute: :id_front, label: "Front ID Card", **options))
  end

  # No `capture`: that is what lets a phone offer its photo library, camera
  # and files instead of opening the camera straight away.
  it "keeps a plain image file input, with no capture, out of the tab order" do
    render_upload

    input = page.find("input[type='file']#booking_id_front", visible: :all)

    expect(input[:accept]).to eq("image/*")
    expect(input[:capture]).to be_nil
    expect(input[:tabindex]).to eq("-1")
    expect(input[:name]).to eq("booking[id_front]")
  end

  it "is one button named by the label, with the hint as its description" do
    render_upload

    expect(page).to have_css(
      "button.guest-image-upload__empty[type='button']" \
      "[aria-labelledby='booking_id_front-label booking_id_front-add'][aria-describedby='booking_id_front-hint']"
    )
    expect(page).to have_css("#booking_id_front-label[data-upload-label]", text: "Front ID Card")
    expect(page).to have_css("#booking_id_front-hint", text: "Photo, gallery or file")
  end

  it "starts empty, or filled with the photo already on the record" do
    render_upload
    expect(page).to have_css(".guest-image-upload[data-state='empty']")

    render_upload(preview_url: "/photo.jpg", required: true)
    expect(page).to have_css(".guest-image-upload[data-state='filled'] img[src='/photo.jpg'][alt='Photo added: Front ID Card']")
    expect(page.find("input[type='file']", visible: :all)[:required]).to be_nil
  end

  it "ties an error to the button" do
    render_upload(error: "Add the front of your ID.")

    expect(page).to have_css(".guest-image-upload[data-invalid='true']")
    expect(page).to have_css("button[aria-describedby='booking_id_front-hint booking_id_front-error']")
    expect(page).to have_css("#booking_id_front-error.guest-field__error", text: "Add the front of your ID.")
  end

  # A phone's own menu is not reliable -- Android 14 and later go straight to
  # the photo picker -- so the choice is the page's own sheet.
  it "offers Take a photo and Choose a photo or file in a labelled sheet" do
    render_upload

    expect(page).to have_css(".guest-image-upload[data-controller='guest-image-upload concierge-modal']")
    sheet = page.find("dialog.guest-sheet[aria-labelledby='booking_id_front-sheet-title']", visible: :all)

    expect(sheet).to have_css("#booking_id_front-sheet-title", text: "Front ID Card", visible: :all)
    expect(sheet).to have_css("button[data-action='guest-image-upload#takePhoto']", text: "Take a photo", visible: :all)
    expect(sheet).to have_css("button[data-action='guest-image-upload#choosePhoto']", text: "Choose a photo or file", visible: :all)
    expect(sheet).to have_css("button[data-action='concierge-modal#close']", text: "Cancel", visible: :all)
  end

  it "announces a chosen photo in a live region" do
    render_upload

    expect(page).to have_css("[aria-live='polite'][data-guest-image-upload-target='status']", visible: :all)
  end
end
