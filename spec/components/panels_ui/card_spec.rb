# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Card, type: :component do
  def render_card(**options, &block)
    render_inline(described_class.new(**options), &block)
  end

  it "renders safe defaults and all structured sections in order" do
    render_card do |card|
      card.with_header(title: "Reservation", description: "Guest details")
      card.with_card_content { "Main content" }
      card.with_footer(align: :between) { "Footer actions" }
    end

    root = page.find("div.panel-card")
    expect(root["data-orientation"]).to eq("vertical")
    expect(root["data-density"]).to eq("default")
    expect(root["data-variant"]).to eq("default")
    expect(root["data-interactive"]).to eq("static")
    expect(root["data-dividers"]).to eq("automatic")
    expect(page).to have_css(".panel-card__sections > header + .panel-card__content + footer")
    expect(page).to have_css(".panel-card__header-row > .panel-card__heading > .panel-card__title + .panel-card__description")
    expect(page).to have_css("footer[data-align='between']", text: "Footer actions")
  end

  it "supports every width, density, variant, orientation, divider mode, and root tag" do
    described_class::WIDTHS.product(
      described_class::DENSITIES,
      described_class::VARIANTS,
      described_class::ORIENTATIONS,
      described_class::DIVIDERS,
      described_class::ROOT_TAGS
    ).each do |width, density, variant, orientation, dividers, root_tag|
      render_card(width: width, density: density, variant: variant, orientation: orientation, dividers: dividers, as: root_tag) do |card|
        card.with_card_content { "#{width}-#{density}" }
      end

      expect(page).to have_css(
        "#{root_tag}.panel-card[data-density='#{density}'][data-variant='#{variant}']" \
        "[data-orientation='#{orientation}'][data-dividers='#{dividers}']"
      )
    end
  end

  it "applies the documented widths" do
    expected = { narrow: "max-w-md", default: "max-w-2xl", expanded: "max-w-5xl", full: "max-w-none" }

    expected.each do |width, css_class|
      render_card(width: width) { |card| card.with_card_content { width.to_s } }
      expect(page).to have_css(".panel-card.#{css_class.gsub(':', '\\:')}")
    end
  end

  it "merges caller classes and standard HTML attributes" do
    render_card(as: :article, class: "mt-8", id: "booking-card", aria: { label: "Booking" }, data: { testid: "card" }) do |card|
      card.with_card_content { "Details" }
    end

    expect(page).to have_css("article#booking-card.panel-card.mt-8[aria-label='Booking'][data-testid='card']")
  end

  it "renders top and leading media with ratios and meaningful alternatives" do
    render_card(orientation: :horizontal) do |card|
      card.with_media(position: :leading, ratio: :square) { '<img src="room.jpg" alt="Deluxe room">'.html_safe }
      card.with_card_content { "Room" }
    end

    expect(page).to have_css(".panel-card[data-media-position='leading'] .panel-card__media[data-position='leading'][data-ratio='square'] img[alt='Deluxe room']")
  end

  it "rejects non-background images without meaningful alternative text" do
    expect do
      render_card do |card|
        card.with_media { '<img src="room.jpg" alt="">'.html_safe }
      end
    end.to raise_error(ArgumentError, /meaningful alt text/)
  end

  it "renders background media as decorative with a mandatory overlay" do
    render_card do |card|
      card.with_media(position: :background, overlay: nil) { '<img src="view.jpg" alt="Scenic view">'.html_safe }
      card.with_header(title: "Waterfront", primary_href: "#waterfront")
    end

    expect(page).to have_css(".panel-card__media[aria-hidden='true'][data-position='background'][data-overlay='default']")
    expect(page).to have_css(".panel-card__media-overlay[aria-hidden='true']")
  end

  it "renders a semantic stretched primary link for clickable cards" do
    render_card(interactive: :clickable) do |card|
      card.with_header(title: "Booking #1042", primary_href: "/bookings/1042") do |header|
        header.with_actions { '<button type="button">More</button>'.html_safe }
      end
      card.with_card_content { '<a href="/guest">Guest</a>'.html_safe }
    end

    expect(page).to have_css(".panel-card[data-interactive='clickable'] h3 .panel-card__primary-link[href='/bookings/1042']")
    expect(page).to have_css(".panel-card__actions button", text: "More")
    expect(page).to have_css(".panel-card__content a[href='/guest']", text: "Guest")
  end

  it "rejects clickable cards without a primary header link" do
    expect do
      render_card(interactive: :clickable) { |card| card.with_card_content { "Missing link" } }
    end.to raise_error(ArgumentError, /primary_href/)

    expect do
      render_card(interactive: :clickable) { |card| card.with_header(title: "Missing link") }
    end.to raise_error(ArgumentError, /primary_href/)
  end

  it "falls back to safe values for unsupported options" do
    render_card(width: :huge, density: :dense, variant: :glass, orientation: :diagonal, dividers: :sometimes, as: :main) do |card|
      card.with_card_content { "Fallback" }
    end

    expect(page).to have_css("div.panel-card.max-w-2xl[data-density='default'][data-variant='default'][data-orientation='vertical'][data-dividers='automatic']")
  end
end
