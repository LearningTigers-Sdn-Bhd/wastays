# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::Card, type: :component do
  it "is a labelled section when it has a title" do
    render_inline(described_class.new(title: "Hotel Services")) { "Body" }

    expect(page).to have_css("section.guest-card h2.guest-card__title", text: "Hotel Services")
    expect(page).to have_css(".guest-card__body", text: "Body")
  end

  it "skips the body wrapper when there is no title to separate from" do
    render_inline(described_class.new) { "Body" }

    expect(page).to have_no_css(".guest-card__title")
    expect(page).to have_no_css(".guest-card__body")
    expect(page).to have_css("section.guest-card", text: "Body")
  end

  it "tightens its padding when asked, and falls back when not understood" do
    render_inline(described_class.new(padding: :tight)) { "Body" }
    expect(page).to have_css(".guest-card[data-padding='tight']")

    render_inline(described_class.new(padding: :roomy)) { "Body" }
    expect(page).to have_css(".guest-card[data-padding='default']")
  end

  it "draws itself dashed for something the hotel already has" do
    render_inline(described_class.new(variant: :dashed)) { "Check-out asked" }

    expect(page).to have_css(".guest-card[data-variant='dashed']")
  end

  describe "the service rows inside it" do
    it "lists each row as a link with its label and hint" do
      render_inline(described_class.new(title: "Booking and Billing")) do |card|
        card.with_row(label: "Booking receipt", hint: "PDF", href: "/receipt")
        card.with_row(label: "E-invoice", href: "/e-invoice")
      end

      expect(page).to have_css("a.guest-card__row[href='/receipt'] .guest-card__row-label", text: "Booking receipt")
      expect(page).to have_css(".guest-card__row-hint", text: "PDF")
      expect(page).to have_css("a.guest-card__row", count: 2)
    end

    it "leaves the hint out when there is none" do
      render_inline(described_class.new) { |card| card.with_row(label: "E-invoice", href: "/x") }

      expect(page).to have_no_css(".guest-card__row-hint")
    end

    it "shows an optional decorative icon for a booking action" do
      render_inline(described_class.new) { |card| card.with_row(label: "Booking receipt", href: "/receipt", icon: "receipt") }

      expect(page).to have_css(".guest-card__row-icon[aria-hidden='true']")
    end

    # A row that changes something is a form, for the same reason a button is.
    it "is a form when the row changes something" do
      render_inline(described_class.new) do |card|
        card.with_row(label: "Resend my link", href: "/resend", method: :post)
      end

      expect(page).to have_css("form[action='/resend'] button.guest-card__row")
    end

    # The row is already a link. A screen reader that read this too would end
    # every service with "right-pointing angle".
    it "hides the chevron from a screen reader" do
      render_inline(described_class.new) { |card| card.with_row(label: "E-invoice", href: "/x") }

      expect(page).to have_css(".guest-card__row-chevron[aria-hidden='true']")
    end

    it "carries the group marker its hover state needs" do
      render_inline(described_class.new) { |card| card.with_row(label: "E-invoice", href: "/x") }

      expect(page).to have_css("a.guest-card__row.group")
    end

    it "asks Turbo to confirm first when told to" do
      render_inline(described_class.new) do |card|
        card.with_row(label: "Cancel", href: "/x", method: :delete, confirm: "Sure?")
      end

      expect(page).to have_css("button.guest-card__row[data-turbo-confirm='Sure?']")
    end
  end
end
