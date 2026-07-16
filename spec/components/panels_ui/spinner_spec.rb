# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Spinner, type: :component do
  it "renders an accessible standalone spinner by default" do
    render_inline(described_class.new)

    expect(page).to have_css("span.panel-spinner[role='status'][aria-label='Loading']:not([data-size]):not([data-variant])")
  end

  it "supports every size and variant" do
    described_class::SIZES.product(described_class::VARIANTS).each do |size, variant|
      render_inline(described_class.new(size: size, variant: variant, aria_label: "#{size}-#{variant}"))
      size_selector = size == :md ? ":not([data-size])" : "[data-size='#{size}']"
      variant_selector = variant == :default ? ":not([data-variant])" : "[data-variant='#{variant}']"

      expect(page).to have_css(".panel-spinner#{size_selector}#{variant_selector}[aria-label='#{size}-#{variant}']")
    end
  end

  it "renders a visible label inside a status wrapper" do
    render_inline(described_class.new(label: "Saving booking…", variant: :primary, class: "mt-2", spinner_class: "shrink-0"))

    expect(page).to have_css("span.panel-loading.mt-2[role='status'][data-orientation='horizontal']", text: "Saving booking…")
    expect(page).to have_css(".panel-loading .panel-spinner.shrink-0[data-variant='primary'][aria-hidden='true']")
  end

  it "renders a vertically oriented loading label" do
    render_inline(described_class.new(label: "Loading rooms…", orientation: :vertical))

    expect(page).to have_css(".panel-loading[data-orientation='vertical']", text: "Loading rooms…")
  end

  it "accepts block content and arbitrary attributes" do
    render_inline(described_class.new(id: "payment", data: { testid: "spinner" }, aria: { live: "assertive" })) do
      "Confirming payment…"
    end

    expect(page).to have_css("#payment.panel-loading[data-testid='spinner'][aria-live='assertive']", text: "Confirming payment…")
  end

  it "falls back for unknown options" do
    render_inline(described_class.new(label: "Fallback", size: :huge, variant: :rainbow, orientation: :diagonal))

    expect(page).to have_css(".panel-loading[data-orientation='horizontal']", text: "Fallback")
    expect(page).to have_css(".panel-spinner:not([data-size]):not([data-variant])")
  end
end
