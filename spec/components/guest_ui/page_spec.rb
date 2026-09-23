# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::Page, type: :component do
  it "gives the content a landmark to skip to" do
    render_inline(described_class.new) { "Actions" }

    expect(page).to have_css(".guest-page main.guest-page__main .guest-page__content", text: "Actions")
  end

  # The stay context sits at about a third and the actions at about two thirds.
  it "splits into two columns when there is context to keep" do
    render_inline(described_class.new) do |shell|
      shell.with_context { "Your stay" }
      "Actions"
    end

    expect(page).to have_css(".guest-page[data-variant='split'] .guest-page__grid[data-columns='2']")
    expect(page).to have_css(".guest-page__context", text: "Your stay")
  end

  # A third of the measure left as white space beside the content reads as a
  # column that failed to load.
  it "gives the content the whole measure when there is no context" do
    render_inline(described_class.new) { "Actions" }

    expect(page).to have_css(".guest-page__grid[data-columns='1']")
    expect(page).to have_no_css(".guest-page__context")
  end

  it "narrows for a page with nothing to keep beside it" do
    render_inline(described_class.new(variant: :centered)) { "This link has ended." }

    expect(page).to have_css(".guest-page[data-variant='centered'] .guest-page__grid[data-columns='1']")
  end

  it "stays one column even with context when it is centered" do
    render_inline(described_class.new(variant: :centered)) do |shell|
      shell.with_context { "Your stay" }
      "Actions"
    end

    expect(page).to have_css(".guest-page__grid[data-columns='1']")
  end

  it "falls back to the layout it has a grid for" do
    render_inline(described_class.new(variant: :fullbleed)) { "Actions" }

    expect(page).to have_css(".guest-page[data-variant='split']")
  end

  # The chat fills the viewport and names the hotel in its own bar, so it takes
  # the frame without one.
  it "takes a hero above the content, and works without one" do
    render_inline(described_class.new) do |shell|
      shell.with_hero { "HERO" }
      "Actions"
    end
    expect(page).to have_text("HERO")

    render_inline(described_class.new) { "Actions" }
    expect(page).to have_css(".guest-page main")
  end

  it "signs the page off, unless the caller would rather it did not" do
    render_inline(described_class.new) { "Actions" }
    expect(page).to have_css("footer.guest-footer", text: "Concierge by WAStays")

    render_inline(described_class.new(footer: false)) { "Actions" }
    expect(page).to have_no_css("footer.guest-footer")
  end
end
