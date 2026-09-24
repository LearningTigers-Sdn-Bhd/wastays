# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::Card, type: :component do
  it "is a labelled section when it has a title" do
    render_inline(described_class.new(title: "Property Services")) { "Body" }

    expect(page).to have_css("section.guest-card h2.guest-card__title", text: "Property Services")
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

    it "opens in a new tab when asked, and tells the eye and the screen reader" do
      render_inline(described_class.new) { |card| card.with_row(label: "Booking receipt", href: "/receipt", new_tab: true) }

      expect(page).to have_css("a.guest-card__row[target='_blank'][rel='noopener']")
      expect(page).to have_css(".guest-card__row-label .sr-only", text: "(opens in a new tab)")
    end

    it "stays in the same tab by default" do
      render_inline(described_class.new) { |card| card.with_row(label: "E-invoice", href: "/x") }

      expect(page).to have_no_css("a[target]")
      expect(page).to have_no_css(".sr-only")
    end

    it "points outward for a call or an email, without the new tab words" do
      render_inline(described_class.new) do |card|
        card.with_row(label: "Call us", href: "tel:+60312345678")
        card.with_row(label: "Email", href: "mailto:desk@example.com")
        card.with_row(label: "Directions", href: "https://maps.example.com", new_tab: true)
        card.with_row(label: "E-invoice", href: "/x")
      end

      call, email, directions, invoice = page.all(".guest-card__row-chevron").map { |icon| icon.native.inner_html }

      expect([ call, email ]).to all(eq(directions))
      expect(invoice).not_to eq(directions)
      expect(page).to have_css("a[target]", count: 1)
      expect(page).to have_css(".sr-only", count: 1)
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
