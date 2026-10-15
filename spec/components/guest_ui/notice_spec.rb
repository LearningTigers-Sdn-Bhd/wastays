# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::Notice, type: :component do
  it "carries the fact in the words, not only in the tint" do
    render_inline(described_class.new(message: "We have your request.", variant: :success))

    expect(page).to have_css(".guest-notice[data-variant='success']", text: "We have your request.")
  end

  it "falls back to the variant it has a tint for" do
    render_inline(described_class.new(message: "Something", variant: :chartreuse))

    expect(page).to have_css(".guest-notice[data-variant='info']")
  end

  # A guest whose form came back invalid has to hear why without hunting for it.
  it "interrupts a screen reader when something went wrong" do
    render_inline(described_class.new(message: "That code did not match.", variant: :danger))

    expect(page).to have_css(".guest-notice[role='alert']")
  end

  it "stays quiet when nothing went wrong" do
    render_inline(described_class.new(message: "We sent a new link.", variant: :success))

    expect(page).to have_no_css("[role='alert']")
  end

  it "lets the caller decide either way" do
    render_inline(described_class.new(message: "Your stay ends today.", variant: :warning, alert: true))
    expect(page).to have_css("[role='alert']")

    render_inline(described_class.new(message: "That code did not match.", variant: :danger, alert: false))
    expect(page).to have_no_css("[role='alert']")
  end

  # Callers pass a message straight from the controller, which is blank on the
  # first visit to every form.
  it "draws nothing at all when there is nothing to say" do
    render_inline(described_class.new(message: nil))

    expect(page.native.to_html).not_to include("guest-notice")
  end

  it "draws nothing for a blank string either" do
    render_inline(described_class.new(message: ""))

    expect(page.native.to_html).not_to include("guest-notice")
  end

  it "prefers its block over the message" do
    render_inline(described_class.new(message: "Ignored")) { "From the block" }

    expect(page).to have_text("From the block")
    expect(page).to have_no_text("Ignored")
  end

  it "sets a title above the message when one is given" do
    render_inline(described_class.new(title: "Refund asked", message: "The property replies to you."))

    expect(page).to have_css(".guest-notice__title", text: "Refund asked")
    expect(page).to have_text("The property replies to you.")
  end

  it "hides its icon, which says nothing the words do not" do
    render_inline(described_class.new(message: "We have your request.", variant: :success))

    expect(page).to have_css(".guest-notice svg[aria-hidden='true']")
  end

  it "drops the icon when a caller wants the words alone" do
    render_inline(described_class.new(message: "We have your request.", icon: false))

    expect(page).to have_no_css(".guest-notice svg")
  end
end
