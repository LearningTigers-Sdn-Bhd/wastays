# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::Button, type: :component do
  it "is a button when nothing says where it goes" do
    render_inline(described_class.new(label: "Send to the hotel"))

    expect(page).to have_css("button.guest-button[type='button']", text: "Send to the hotel")
    expect(page).to have_css(".guest-button[data-variant='primary'][data-size='md']")
  end

  it "is a link when it only goes somewhere" do
    render_inline(described_class.new(label: "Back", href: "/stay", variant: :ghost, size: :sm))

    expect(page).to have_css("a.guest-button[href='/stay'][data-variant='ghost'][data-size='sm']", text: "Back")
  end

  # Anything that changes something is a form. A link that changes something is
  # a link a browser is free to follow on its own.
  it "is a form when it changes something" do
    render_inline(described_class.new(label: "Email me a new link", href: "/recovery", method: :post))

    expect(page).to have_css("form[action='/recovery'][method='post'] button.guest-button", text: "Email me a new link")
  end

  it "carries a method a form cannot send on its own" do
    render_inline(described_class.new(label: "Switch", href: "/dnd", method: :patch))

    expect(page).to have_css("input[name='_method'][value='patch']", visible: :all)
  end

  it "fills the column it sits in when asked" do
    render_inline(described_class.new(label: "Verify this device", block: true))

    expect(page).to have_css(".guest-button[data-block='true']")
  end

  # button_to shrink-wraps its form, so a block button inside one would be as
  # wide as its word rather than as wide as the column.
  it "collapses the form wrapper so a block form button still fills its column" do
    render_inline(described_class.new(label: "Ask again", href: "/x", method: :post, block: true))

    expect(page).to have_css("form.contents button.guest-button[data-block='true']")
  end

  it "falls back to the variant and size it has colours for" do
    render_inline(described_class.new(label: "Go", variant: :neon, size: :enormous))

    expect(page).to have_css(".guest-button[data-variant='primary'][data-size='md']")
  end

  it "prefers its block over the label" do
    render_inline(described_class.new(label: "Ignored")) { "From the block" }

    expect(page).to have_text("From the block")
    expect(page).to have_no_text("Ignored")
  end

  describe "an icon" do
    it "hides it from a screen reader, because the word beside it already says so" do
      render_inline(described_class.new(label: "Download the e-invoice", icon: "download"))

      expect(page).to have_css(".guest-button svg[aria-hidden='true']")
      expect(page).to have_text("Download the e-invoice")
    end

    it "refuses to draw an icon on its own without a name" do
      expect { render_inline(described_class.new(icon: "x", icon_only: true)) }
        .to raise_error(ArgumentError, /aria_label/)
    end

    it "takes the name from aria_label" do
      render_inline(described_class.new(icon: "x", icon_only: true, aria_label: "Close"))

      expect(page).to have_css(".guest-button[aria-label='Close'][data-icon-only='true']")
    end

    it "takes the name from an aria hash too" do
      render_inline(described_class.new(icon: "x", icon_only: true, aria: { label: "Close" }))

      expect(page).to have_css(".guest-button[aria-label='Close']")
    end
  end

  describe "disabled" do
    it "sets the attribute a button has" do
      render_inline(described_class.new(label: "Wait", disabled: true))

      expect(page).to have_css("button.guest-button[disabled]")
    end

    # A link has no disabled attribute. Leaving the href would make a guest on a
    # keyboard or a screen reader the only one who could still press it.
    it "takes a link out of the tab order and off its destination" do
      render_inline(described_class.new(label: "Gone", href: "/x", disabled: true))

      expect(page).to have_css("a.guest-button[aria-disabled='true'][tabindex='-1']")
      expect(page).to have_no_css("a[href]")
    end
  end

  it "asks Turbo to confirm first when told to" do
    render_inline(described_class.new(label: "Cancel my stay", href: "/x", method: :delete, confirm: "Are you sure?"))

    expect(page).to have_css("button.guest-button[data-turbo-confirm='Are you sure?']")
  end
end
