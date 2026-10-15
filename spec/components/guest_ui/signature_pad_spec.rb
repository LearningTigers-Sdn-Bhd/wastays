# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::SignaturePad, type: :component do
  def render_pad(**options)
    form = ActionView::Helpers::FormBuilder.new(:booking, nil, vc_test_view_context, {})
    render_inline(described_class.new(form: form, attribute: :signature, label: "Your signature", **options))
  end

  it "puts the pad and its footer in one labelled group" do
    render_pad

    expect(page).to have_css(".guest-signature-pad[data-controller='signature']")
    expect(page).to have_css(
      "[role='group'].guest-signature-pad__frame[aria-labelledby='booking_signature-label'][aria-describedby='booking_signature-status']"
    )
    expect(page).to have_css(".guest-signature-pad__frame canvas[data-signature-target='canvas']", visible: :all)
    expect(page).to have_css(".guest-signature-pad__footer [aria-live='polite'][data-signature-target='status']", text: "Sign in the box")
  end

  # Nothing to clear until the guest signs; the controller enables it.
  it "starts with Clear disabled, named for what it clears" do
    render_pad

    expect(page).to have_css(
      "button.guest-signature-pad__clear[type='button'][disabled][aria-label='Clear signature']" \
      "[data-signature-target='clearButton'][data-action='signature#clear']", text: "Clear"
    )
  end

  # type=hidden is skipped when the browser checks `required`; a text field
  # hidden from sight is not.
  it "keeps the signature in a checkable field out of the tab order" do
    render_pad(required: true)

    input = page.find("input#booking_signature", visible: :all)

    expect(input[:type]).to eq("text")
    expect(input[:required]).to be_present
    expect(input[:tabindex]).to eq("-1")
    expect(input[:"data-signature-target"]).to eq("input")
    expect(page).to have_css("#booking_signature-label .sr-only", text: "(required)")
  end

  it "ties an error to the group" do
    render_pad(error: "Please sign in the box.")

    expect(page).to have_css(".guest-signature-pad[data-invalid='true']")
    expect(page).to have_css("[role='group'][aria-describedby='booking_signature-status booking_signature-error']")
    expect(page).to have_css("#booking_signature-error", text: "Please sign in the box.")
  end
end
