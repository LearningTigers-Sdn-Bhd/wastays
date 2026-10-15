# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::FormField, type: :component do
  GuestFieldObject = Class.new do
    include ActiveModel::Model
    attr_accessor :details, :refund_amount, :account_type
  end

  def form_for(object = GuestFieldObject.new)
    ActionView::Helpers::FormBuilder.new(:stay, object, vc_test_view_context, {})
  end

  def render_field(object: GuestFieldObject.new, attribute: :details, **options, &block)
    render_inline(described_class.new(form: form_for(object), attribute: attribute, **options), &block)
  end

  it "points the label at the control it drew" do
    render_field(label: "What do you need?") { |field| field.with_text_area }

    expect(page).to have_css("label#stay_details-label[for='stay_details']", text: "What do you need?")
    expect(page).to have_css("textarea#stay_details.guest-text-area")
  end

  it "keeps the label readable by a screen reader when the page hides it" do
    render_field(label: "What do you need?", label_hidden: true) { |field| field.with_text_area }

    expect(page).to have_css("label.guest-field__label.sr-only", text: "What do you need?")
  end

  it "marks a required field for both eyes and ears" do
    render_field(label: "Details", required: true) { |field| field.with_text_area }

    expect(page).to have_css(".guest-field__required[aria-hidden='true']", text: "*")
    expect(page).to have_css(".sr-only", text: "(required)")
    expect(page).to have_css("textarea[required]")
  end

  it "ties a hint to the control that carries it" do
    render_field(label: "Details", hint: "Tell us what is wrong.") { |field| field.with_text_area }

    expect(page).to have_css("p#stay_details-hint.guest-field__hint", text: "Tell us what is wrong.")
    expect(page).to have_css("textarea[aria-describedby='stay_details-hint']")
  end

  it "reads the error off the model when the caller names none" do
    object = GuestFieldObject.new
    object.errors.add(:details, "cannot be blank")

    render_field(object: object, label: "Details") { |field| field.with_text_area }

    expect(page).to have_css("p#stay_details-error.guest-field__error", text: "cannot be blank")
    expect(page).to have_css("textarea[aria-invalid='true'][aria-describedby='stay_details-error']")
    expect(page).to have_css(".guest-field[data-invalid='true']")
  end

  it "takes an error the caller passes instead" do
    render_field(label: "Details", error: "That code did not match.") { |field| field.with_text_area }

    expect(page).to have_css(".guest-field__error", text: "That code did not match.")
  end

  # A guest reading a field that came back invalid needs the one line that says
  # what to change. The hint under it is the advice they already followed.
  it "shows the error instead of the hint, never both" do
    render_field(label: "Details", hint: "Tell us what is wrong.", error: "cannot be blank") do |field|
      field.with_text_area
    end

    expect(page).to have_css(".guest-field__error")
    expect(page).to have_no_css(".guest-field__hint")
    expect(page).to have_no_text("Tell us what is wrong.")
  end

  it "keeps the hint when an explicit nil error says there is none" do
    object = GuestFieldObject.new
    object.errors.add(:details, "cannot be blank")

    render_field(object: object, label: "Details", hint: "Still useful.", error: nil) { |field| field.with_text_area }

    expect(page).to have_css(".guest-field__hint", text: "Still useful.")
    expect(page).to have_no_css(".guest-field__error")
  end

  it "works without a label, for a control the page already introduced" do
    render_field { |field| field.with_text_area }

    expect(page).to have_no_css("label")
    expect(page).to have_css("textarea#stay_details")
  end

  it "refuses to draw a field with nothing in it" do
    expect { render_field(label: "Details") }.to raise_error(ArgumentError, /require a control/)
  end

  it "gives the control its own id when two forms share a page" do
    render_field(label: "Details", id: "second-details") { |field| field.with_text_area }

    expect(page).to have_css("label[for='second-details'][id='second-details-label']")
    expect(page).to have_css("textarea#second-details")
  end

  describe "the controls it composes" do
    it "composes an input" do
      render_field(attribute: :refund_amount, label: "How much?") { |field| field.with_input(type: :number) }

      expect(page).to have_css("input#stay_refund_amount.guest-input[type='number']")
    end

    it "lets a control keep a size of its own" do
      render_field(label: "Code", size: :md) { |field| field.with_input(size: :lg) }

      expect(page).to have_css(".guest-field[data-size='md']")
      expect(page).to have_css(".guest-input[data-size='lg']")
    end

    # A radio group has no element of its own for a label to point at, so it
    # names itself with the label's id instead.
    it "names a radio group by the label rather than pointing at it" do
      render_field(attribute: :account_type, label: "Account type") do |field|
        field.with_radio_group(choices: %w[savings current])
      end

      expect(page).to have_css("div[role='radiogroup'][aria-labelledby='stay_account_type-label']")
      expect(page).to have_css("input#stay_account_type[type='radio']")
    end
  end
end
