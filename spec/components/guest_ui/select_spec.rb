# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::Select, type: :component do
  GuestSelectObject = Class.new do
    include ActiveModel::Model
    attr_accessor :bank_name
  end

  def render_select(bank_name: nil, **options)
    form = ActionView::Helpers::FormBuilder.new(:refund, GuestSelectObject.new(bank_name: bank_name), vc_test_view_context, {})
    render_inline(described_class.new(form: form, attribute: :bank_name,
                                      choices: [ %w[CIMB CIMB], %w[Maybank Maybank] ], prompt: "Choose your bank", **options))
  end

  # The native select carries the value and is what a guest without
  # JavaScript uses, so it keeps the field id the label points at.
  it "keeps a native select as the source of truth" do
    render_select(required: true)

    expect(page).to have_css("select#refund_bank_name[name='refund[bank_name]'][required][data-ui--select-menu-target='native']")
    expect(page).to have_css("select#refund_bank_name option", text: "Choose your bank")
  end

  it "puts the page's own data on the native select, after its own action" do
    render_select(native_data: { guest_identity_target: "documentType", action: "change->guest-identity#documentChanged" })

    expect(page).to have_css(
      "select[data-guest-identity-target='documentType']" \
      "[data-action='change->ui--select-menu#onNativeChange change->guest-identity#documentChanged']"
    )
  end

  it "caps the listbox height" do
    render_select

    expect(page).to have_css(".guest-select[data-ui--select-menu-max-height-value='280']")
  end

  it "names the trigger by the field label and the value" do
    render_select(labelled_by: "refund_bank_name-label")

    expect(page).to have_css(
      "button#refund_bank_name-trigger[aria-haspopup='listbox'][aria-expanded='false']" \
      "[aria-controls='refund_bank_name-listbox'][aria-labelledby='refund_bank_name-label refund_bank_name-value']"
    )
    expect(page).to have_css("#refund_bank_name-value[data-placeholder='true']", text: "Choose your bank")
  end

  it "lists each choice as an option and marks the current one" do
    render_select(bank_name: "Maybank")

    expect(page).to have_css("[role='listbox'] [role='option']", count: 2)
    expect(page).to have_css("[role='option'][aria-selected='true'][data-value='Maybank'] [data-select-menu-label]", text: "Maybank")
    expect(page).to have_css("#refund_bank_name-value[data-placeholder='false']", text: "Maybank")
  end

  it "reports invalid on the native select and the trigger" do
    render_select(invalid: true, described_by: "refund_bank_name-error")

    expect(page).to have_css("select[aria-invalid='true'][aria-describedby='refund_bank_name-error']")
    expect(page).to have_css("button[aria-invalid='true'][aria-describedby='refund_bank_name-error']")
  end
end
