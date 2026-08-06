# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::MetricCard, type: :component do
  it "requires a label and a value unless loading" do
    expect { described_class.new(label: nil, value: "82%") }
      .to raise_error(ArgumentError, /require a label/)
    expect { described_class.new(label: "Occupancy") }
      .to raise_error(ArgumentError, /require a value unless loading/)

    render_inline(described_class.new(label: "Occupancy", loading: true))

    expect(page).to have_css("article.panel-metric-card[aria-busy='true']", text: "Loading Occupancy")
  end

  it "renders compact static metrics by default" do
    render_inline(described_class.new(label: "Occupancy", value: "82%", detail: "41 of 50 rooms"))

    expect(page).to have_css("article.panel-metric-card[data-density='compact'][data-interactive='false']")
    expect(page).to have_css(".panel-metric-card__label", text: "Occupancy")
    expect(page).to have_css(".panel-metric-card__value", text: "82%")
    expect(page).to have_css(".panel-metric-card__detail[data-variant='neutral']", text: "41 of 50 rooms")
  end

  it "supports every density and detail variant" do
    described_class::DENSITIES.product(described_class::DETAIL_VARIANTS).each do |density, detail_variant|
      render_inline(described_class.new(
        label: "Revenue", value: "MYR 18,420", detail: "Trend",
        density: density, detail_variant: detail_variant
      ))

      expect(page).to have_css(
        ".panel-metric-card[data-density='#{density}'] " \
        ".panel-metric-card__detail[data-variant='#{detail_variant}']"
      )
    end
  end

  it "renders icons, links, loading state, caller classes, and HTML attributes" do
    render_inline(described_class.new(
      label: "Open folios", value: "24", icon: "receipt-text", href: "/folios",
      class: "h-full", id: "open-folios", data: { testid: "metric" },
      aria: { label: "Open folios summary" }
    ))

    expect(page).to have_css(
      "a#open-folios.panel-metric-card.h-full[href='/folios'][data-testid='metric']" \
      "[data-interactive='true'][aria-label='Open folios summary']"
    )
    expect(page).to have_css(".panel-metric-card__icon[aria-hidden='true']")

    render_inline(described_class.new(label: "Revenue", loading: true))

    expect(page).to have_css(".panel-metric-card[data-loading='true'][aria-busy='true'] .panel-metric-card__loading")
    expect(page).to have_css(".panel-metric-card__loading .panel-skeleton", count: 3)
  end

  it "falls back to compact density and a neutral detail variant" do
    render_inline(described_class.new(
      label: "Occupancy", value: "82%", detail: "Stable",
      density: :dense, detail_variant: :positive
    ))

    expect(page).to have_css(".panel-metric-card[data-density='compact'] .panel-metric-card__detail[data-variant='neutral']")
  end
end
