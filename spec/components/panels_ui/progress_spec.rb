# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Progress, type: :component do
  it "renders determinate native progress with caller attributes" do
    render_inline(described_class.new(
      value: 62, max: 100, variant: :info, size: :lg, label: "Data import",
      class: "mt-2", id: "import", data: { testid: "progress" }
    ))

    expect(page).to have_css("progress#import.panel-progress.mt-2[value='62'][max='100'][data-variant='info'][data-size='lg'][aria-label='Data import'][data-testid='progress']")
  end

  it "clamps determinate values to the valid range" do
    render_inline(described_class.new(value: 120, max: 100, label: "High"))
    expect(page).to have_css("progress[value='100']", count: 1)

    render_inline(described_class.new(value: -10, max: 100, label: "Low"))
    expect(page).to have_css("progress[value='0']", count: 1)
  end

  it "renders an indeterminate accessible track" do
    render_inline(described_class.new(label: "Preparing audit", variant: :warning))

    expect(page).to have_css(".panel-progress[role='progressbar'][data-state='indeterminate'][data-variant='warning'][aria-label='Preparing audit']")
    expect(page).to have_css(".panel-progress__indicator")
    expect(page).to have_no_css("progress")
  end

  it "supports every variant and size and falls back for unknown options" do
    described_class::VARIANTS.product(described_class::SIZES).each do |variant, size|
      render_inline(described_class.new(value: 1, variant: variant, size: size, label: "#{variant}-#{size}"))
      variant_selector = variant == :primary ? ":not([data-variant])" : "[data-variant='#{variant}']"
      size_selector = size == :md ? ":not([data-size])" : "[data-size='#{size}']"
      expect(page).to have_css("progress.panel-progress#{variant_selector}#{size_selector}")
    end
    render_inline(described_class.new(value: 1, variant: :unknown, size: :huge, label: "Fallback"))

    expect(page).to have_css("progress.panel-progress[aria-label='Fallback']:not([data-variant]):not([data-size])")
  end

  it "rejects invalid numeric input and a non-positive maximum" do
    expect { described_class.new(value: 1, max: 0) }.to raise_error(ArgumentError, "max must be greater than zero")
    expect { described_class.new(value: "many", max: 100) }.to raise_error(ArgumentError, "value and max must be numeric")
  end
end
