# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Badge, type: :component do
  it "renders safe defaults and block content" do
    render_inline(described_class.new) { "Confirmed" }

    expect(page).to have_css("span.panel-badge[data-variant='neutral'][data-size='md']", text: "Confirmed")
  end

  it "supports every variant and size" do
    described_class::VARIANTS.product(described_class::SIZES).each do |variant, size|
      render_inline(described_class.new(label: "#{variant}-#{size}", variant: variant, size: size))
      expect(page).to have_css(".panel-badge[data-variant='#{variant}'][data-size='#{size}']", text: "#{variant}-#{size}")
    end
  end

  it "renders rounded indicators, inverse styling, icons, and caller attributes" do
    render_inline(described_class.new(
      shape: :rounded, indicator: true, inverse: true, variant: :success,
      class: "ml-2", id: "status", data: { testid: "badge" }, aria: { label: "Booking status" }
    )) { '<svg aria-hidden="true"></svg> Confirmed'.html_safe }

    expect(page).to have_css("#status.panel-badge-rounded.ml-2[data-testid='badge'][data-indicator='true'][data-inverse='true'][aria-label='Booking status'] svg")
  end

  it "falls back for unknown options" do
    render_inline(described_class.new(label: "Fallback", variant: :bogus, size: :huge, shape: :pillish))

    expect(page).to have_css(".panel-badge[data-variant='neutral'][data-size='md']", text: "Fallback")
  end
end
