# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::MetricStrip, type: :component do
  it "renders compact report metrics through PanelsUI metric cards" do
    render_inline(described_class.new(
      aria_label: "Revenue summary",
      metrics: [
        { label: "Gross bookings", value: "MYR 42,860.00", detail: "18 reservations" },
        { label: "Net earnings", value: "MYR 36,412.00", detail: "85.0% retained", detail_variant: :success },
        { label: "Average booking", value: "MYR 2,381.11" }
      ]
    ))

    expect(page).to have_css("section[data-slot='report-metric-strip'][aria-label='Revenue summary']")
    expect(page).to have_css("[data-slot='report-metric']", count: 3)
    expect(page).to have_css(".panel-metric-card[data-density='compact']", count: 3)
    expect(page).to have_css(
      "section.overflow-hidden.rounded-lg.border.border-border.bg-border.gap-px " \
      ".panel-metric-card.rounded-none.border-0.shadow-none",
      count: 3
    )
    expect(page).to have_css(".panel-metric-card__detail[data-variant='success']", text: "85.0% retained")
  end

  it "rejects empty and oversized metric collections" do
    expect { described_class.new(metrics: []) }.to raise_error(ArgumentError, /one to six metrics/)
    metrics = Array.new(7) { |index| { label: "Metric #{index}", value: index.to_s } }
    expect { described_class.new(metrics:) }.to raise_error(ArgumentError, /one to six metrics/)
  end

  it "stacks below tablet width and uses the exact responsive columns for every supported count" do
    expected_classes = {
      1 => "grid gap-px overflow-hidden rounded-lg border border-border bg-border grid-cols-1",
      2 => "grid gap-px overflow-hidden rounded-lg border border-border bg-border grid-cols-1 md:grid-cols-2",
      3 => "grid gap-px overflow-hidden rounded-lg border border-border bg-border grid-cols-1 md:grid-cols-2 xl:grid-cols-3",
      4 => "grid gap-px overflow-hidden rounded-lg border border-border bg-border grid-cols-1 md:grid-cols-2 xl:grid-cols-4",
      5 => "grid gap-px overflow-hidden rounded-lg border border-border bg-border grid-cols-1 md:grid-cols-2 xl:grid-cols-5",
      6 => "grid gap-px overflow-hidden rounded-lg border border-border bg-border grid-cols-1 md:grid-cols-2 xl:grid-cols-3"
    }

    expected_classes.each do |count, classes|
      metrics = Array.new(count) { |index| { label: "Metric #{index + 1}", value: index.to_s } }
      render_inline(described_class.new(metrics:))

      expect(page.find("section[data-slot='report-metric-strip']")[:class]).to eq(classes)
    end
  end
end
