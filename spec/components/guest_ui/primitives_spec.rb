# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GuestUI primitives", type: :component do
  def form_for_object(object, scope: :refund_request)
    ActionView::Helpers::FormBuilder.new(scope, object, vc_test_controller.view_context, {})
  end

  it "renders a button, a link, and a form button" do
    render_inline(GuestUI::Button.new(label: "Send", icon: "send", block: true))
    expect(page).to have_css("button.guest-button[data-variant='primary'][data-size='md'][data-block='true']", text: "Send")

    render_inline(GuestUI::Button.new(label: "Back", href: "/x", variant: :ghost))
    expect(page).to have_css("a.guest-button[href='/x'][data-variant='ghost']", text: "Back")

    render_inline(GuestUI::Button.new(label: "Resend", href: "/x", method: :post))
    expect(page).to have_css("form[action='/x'] button.guest-button", text: "Resend")

    render_inline(GuestUI::Button.new(label: "Gone", href: "/x", disabled: true))
    expect(page).to have_css("a.guest-button[aria-disabled='true'][tabindex='-1']")
    expect(page).to have_no_css("a[href]")
  end

  it "raises when an icon-only button has no name" do
    expect { render_inline(GuestUI::Button.new(icon: "x", icon_only: true)) }
      .to raise_error(ArgumentError, /aria_label/)
  end

  it "wires a field to its control, hint, and error" do
    form = form_for_object(RefundRequest.new)
    render_inline(GuestUI::FormField.new(form: form, attribute: :reason, label: "Why?", hint: "Tell us.", required: true)) do |field|
      field.with_text_area(rows: 5)
    end
    id = "refund_request_reason"
    expect(page).to have_css("label[for='#{id}'][id='#{id}-label']", text: "Why?")
    expect(page).to have_css("textarea##{id}.guest-text-area[rows='5'][aria-describedby='#{id}-hint'][required]")
    expect(page).to have_css("p##{id}-hint", text: "Tell us.")
    expect(page).to have_css(".sr-only", text: "(required)")
  end

  it "shows the model error instead of the hint" do
    object = RefundRequest.new
    object.errors.add(:refund_amount, "is too large")
    form = form_for_object(object)
    render_inline(GuestUI::FormField.new(form: form, attribute: :refund_amount, label: "How much?", hint: "Not shown")) do |field|
      field.with_input(type: :number)
    end
    id = "refund_request_refund_amount"
    expect(page).to have_css("input##{id}[aria-invalid='true'][aria-describedby='#{id}-error']")
    expect(page).to have_css("p##{id}-error", text: "is too large")
    expect(page).to have_no_text("Not shown")
  end

  it "renders a code input with autocorrect off" do
    form = form_for_object(RefundRequest.new)
    render_inline(GuestUI::Input.new(form: form, attribute: :reason, variant: :code))
    expect(page).to have_css("input.guest-input[data-variant='code'][autocapitalize='characters'][autocorrect='off'][spellcheck='false']")
  end

  it "names a radio group by its field label and keeps native radios" do
    form = form_for_object(RefundRequest.new)
    render_inline(GuestUI::FormField.new(form: form, attribute: :account_type, label: "Account type")) do |field|
      field.with_radio_group(choices: RefundRequest::ACCOUNT_TYPES)
    end
    id = "refund_request_account_type"
    expect(page).to have_css("div[role='radiogroup'][aria-labelledby='#{id}-label']")
    expect(page).to have_css("label.guest-radio-group__option input[type='radio']", count: RefundRequest::ACCOUNT_TYPES.size)
    expect(page).to have_css("input##{id}")
  end

  it "renders a switch that posts and reports its state" do
    render_inline(GuestUI::Switch.new(label: "Do not disturb", hint: "Housekeeping keeps away.", url: "/dnd", checked: true))
    expect(page).to have_css("form[action='/dnd'] button.guest-switch[role='switch'][aria-checked='true']")
    expect(page).to have_css("input[name='_method'][value='patch']", visible: :all)
    expect(page).to have_css(".guest-switch__track[aria-hidden='true']")
    expect(page).to have_text("Do not disturb")
  end

  it "renders notices and draws nothing when empty" do
    render_inline(GuestUI::Notice.new(message: "That code did not match.", variant: :danger))
    expect(page).to have_css(".guest-notice[data-variant='danger'][role='alert']", text: "That code did not match.")
    expect(page).to have_css(".guest-notice svg")

    render_inline(GuestUI::Notice.new(message: "We sent a new link.", variant: :success))
    expect(page).to have_css(".guest-notice[data-variant='success']")
    expect(page).to have_no_css("[role='alert']")

    render_inline(GuestUI::Notice.new(message: nil))
    expect(page.native.to_html).not_to include("guest-notice")
  end

  it "renders a card with rows" do
    render_inline(GuestUI::Card.new(title: "Hotel Services")) do |card|
      card.with_row(label: "Report a problem", href: "/p", hint: "Tell the team.")
      card.with_row(label: "Resend link", href: "/r", method: :post)
    end
    expect(page).to have_css("section.guest-card h2.guest-card__title", text: "Hotel Services")
    expect(page).to have_css("a.guest-card__row[href='/p'] .guest-card__row-label", text: "Report a problem")
    expect(page).to have_css(".guest-card__row-hint", text: "Tell the team.")
    expect(page).to have_css("form[action='/r'] button.guest-card__row")
    expect(page).to have_css(".guest-card__row-chevron[aria-hidden='true']")
  end

  it "renders the split page and falls back to one column" do
    render_inline(GuestUI::Page.new) do |p|
      p.with_hero { "HERO" }
      p.with_context { "CONTEXT" }
      "ACTIONS"
    end
    expect(page).to have_css(".guest-page[data-variant='split'] .guest-page__grid[data-columns='2']")
    expect(page).to have_css("main.guest-page__main .guest-page__context", text: "CONTEXT")
    expect(page).to have_text("Powered by WAStays")

    render_inline(GuestUI::Page.new(variant: :centered, footer: false)) { "ONLY" }
    expect(page).to have_css(".guest-page[data-variant='centered'] .guest-page__grid[data-columns='1']")
    expect(page).to have_no_text("Powered by WAStays")
  end
end
