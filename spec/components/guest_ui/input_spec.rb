# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::Input, type: :component do
  GuestInputObject = Class.new do
    include ActiveModel::Model
    attr_accessor :confirmation_token, :refund_amount
  end

  def form_for(object = GuestInputObject.new)
    ActionView::Helpers::FormBuilder.new(:stay, object, vc_test_view_context, {})
  end

  def render_input(attribute: :confirmation_token, **options)
    render_inline(described_class.new(form: form_for, attribute: attribute, **options))
  end

  it "takes its id from the form, so a label can point at it" do
    render_input

    expect(page).to have_css("input#stay_confirmation_token.guest-input[name='stay[confirmation_token]']")
    expect(page).to have_css(".guest-input[data-size='md'][data-variant='default']")
  end

  it "accepts an id of its own when two forms share a page" do
    render_input(id: "second-stay-token")

    expect(page).to have_css("input#second-stay-token")
  end

  it "picks the field a type asks for" do
    render_input(attribute: :refund_amount, type: :number)

    expect(page).to have_css("input[type='number']")
  end

  it "falls back to text for a type it does not have" do
    render_input(type: :colour)

    expect(page).to have_css("input[type='text']")
  end

  it "falls back to the size it has padding for" do
    render_input(size: :enormous)

    expect(page).to have_css(".guest-input[data-size='md']")
  end

  # A confirmation code is not a word, so the phone must not treat it as one.
  # Autocorrect turns a code into a near miss, and the only report back is that
  # the code was wrong.
  it "stops a phone correcting a confirmation code" do
    render_input(variant: :code)

    expect(page).to have_css(
      ".guest-input[data-variant='code'][autocomplete='off'][autocapitalize='characters'][autocorrect='off'][spellcheck='false']"
    )
  end

  it "lets the caller override what the code variant assumes" do
    render_input(variant: :code, autocomplete: "one-time-code")

    expect(page).to have_css(".guest-input[autocomplete='one-time-code']")
  end

  it "reports that it is invalid and says where the reason is" do
    render_input(invalid: true, described_by: "stay_confirmation_token-error")

    expect(page).to have_css(".guest-input[aria-invalid='true'][aria-describedby='stay_confirmation_token-error']")
  end

  it "says nothing about validity when it is fine" do
    render_input

    expect(page).to have_no_css("[aria-invalid]")
    expect(page).to have_no_css("[aria-describedby]")
  end

  it "joins a description of its own to the one the field gave it" do
    render_input(described_by: "field-hint", aria: { describedby: "extra" })

    expect(page).to have_css(".guest-input[aria-describedby='extra field-hint']")
  end

  it "carries required, disabled, and readonly" do
    render_input(required: true, disabled: true, readonly: true)

    expect(page).to have_css("input[required][disabled][readonly]")
  end
end
