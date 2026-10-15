# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::RadioGroup, type: :component do
  GuestRadioObject = Class.new do
    include ActiveModel::Model
    attr_accessor :account_type
  end

  def render_group(choices: %w[savings current], **options)
    form = ActionView::Helpers::FormBuilder.new(:refund, GuestRadioObject.new, vc_test_view_context, {})
    render_inline(described_class.new(form: form, attribute: :account_type, choices: choices, **options))
  end

  # The native radio is what makes the group one tab stop with the arrow keys
  # moving inside it. Rebuilding that in script is how a form stops working for
  # a guest on a screen reader.
  it "keeps a native radio behind every tile" do
    render_group

    expect(page).to have_css("label.guest-radio-group__option input[type='radio'][name='refund[account_type]']", count: 2)
  end

  it "makes the whole tile the label, so the tap target is the option" do
    render_group

    expect(page).to have_css("label.guest-radio-group__option", count: 2)
    expect(page).to have_css("label.guest-radio-group__option", text: "Savings")
  end

  # A group has no element of its own to focus, so a label read out or clicked
  # has to land on a radio, and the first one is where the group starts.
  it "gives the first option the id the field label points at" do
    render_group

    expect(page).to have_css("input#refund_account_type[value='savings']")
    expect(page).to have_css("input#refund_account_type-1[value='current']")
  end

  it "titleizes a bare value and takes a label when given one" do
    render_group(choices: [ "savings", [ "Current account", "current" ], { label: "Joint", value: "joint" } ])

    expect(page).to have_css(".guest-radio-group__option", text: "Savings")
    expect(page).to have_css(".guest-radio-group__option", text: "Current account")
    expect(page).to have_css(".guest-radio-group__option", text: "Joint")
  end

  it "names each radio by its label and reads its hint as the description" do
    render_group(choices: [ { label: "Savings", value: "savings", hint: "Most personal accounts" }, "current" ])

    expect(page).to have_css("input#refund_account_type[aria-labelledby='refund_account_type-label'][aria-describedby='refund_account_type-hint']")
    expect(page).to have_css("#refund_account_type-hint.guest-radio-group__hint", text: "Most personal accounts")
    expect(page).to have_css("input#refund_account_type-1[aria-labelledby='refund_account_type-1-label']:not([aria-describedby])")
  end

  it "is a radiogroup a screen reader can announce as one thing" do
    render_group(labelled_by: "refund_account_type-label", described_by: "refund_account_type-hint")

    expect(page).to have_css(
      "div[role='radiogroup'][aria-labelledby='refund_account_type-label'][aria-describedby='refund_account_type-hint']"
    )
  end

  it "reports required and invalid on the group, not on one tile" do
    render_group(required: true, invalid: true)

    expect(page).to have_css("[role='radiogroup'][aria-required='true'][aria-invalid='true']")
    expect(page).to have_css("input[type='radio'][required]", count: 2)
  end

  it "stacks when the labels are too long to sit side by side" do
    render_group(layout: :stacked)

    expect(page).to have_css(".guest-radio-group[data-layout='stacked']")
  end

  it "falls back to the layout it has rules for" do
    render_group(layout: :masonry)

    expect(page).to have_css(".guest-radio-group[data-layout='inline']")
  end

  it "disables every option at once" do
    render_group(disabled: true)

    expect(page).to have_css("input[type='radio'][disabled]", count: 2)
  end

  it "draws nothing to choose from when there is nothing to choose" do
    render_group(choices: [])

    expect(page).to have_css("[role='radiogroup']")
    expect(page).to have_no_css("input[type='radio']")
  end
end
