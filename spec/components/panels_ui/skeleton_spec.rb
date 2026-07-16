# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Skeleton, type: :component do
  it "renders every single-placeholder variant" do
    %i[line block square circle].each do |variant|
      render_inline(described_class.new(variant: variant, class: "h-4", data: { kind: variant }))
      expect(page).to have_css(".panel-skeleton.h-4[data-variant='#{variant}'][data-kind='#{variant}'][aria-hidden='true']")
      expect(page).to have_css(".panel-skeleton[data-shape='#{variant}']") if %i[square circle].include?(variant)
    end
  end

  it "falls back to a block" do
    render_inline(described_class.new(variant: :unknown))

    expect(page).to have_css(".panel-skeleton[data-variant='block']")
  end

  it "renders a labeled table preset from an integer column count" do
    render_inline(described_class.new(variant: :table, rows: 2, columns: 3, label: "Loading guests", id: "guest-loading"))

    expect(page).to have_css("#guest-loading.panel-skeleton-table[aria-busy='true'][aria-label='Loading guests'][data-variant='table']")
    expect(page).to have_css(".panel-skeleton-table__row", count: 2)
    expect(page).to have_css(".panel-skeleton-table__row .panel-skeleton-table__cell", count: 6, visible: :all)
    expect(page).to have_css(".sr-only", text: "Loading guests", visible: :all)
  end

  it "applies per-column width classes" do
    render_inline(described_class.new(variant: :table, rows: 1, columns: [ "w-1/2", "w-3/4" ]))

    expect(page).to have_css(".panel-skeleton-table__cell[class~='w-1/2']", count: 1, visible: :all)
    expect(page).to have_css(".panel-skeleton-table__cell[class~='w-3/4']", count: 1, visible: :all)
  end
end
