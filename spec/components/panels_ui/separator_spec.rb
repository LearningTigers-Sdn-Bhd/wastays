# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Separator, type: :component do
  it "renders a semantic horizontal separator by default" do
    render_inline(described_class.new(class: "my-4", id: "divider", data: { testid: "separator" }))

    expect(page).to have_css("#divider.panel-separator.my-4[role='separator'][aria-orientation='horizontal'][data-orientation='horizontal'][data-testid='separator']")
  end

  it "renders a vertical separator" do
    render_inline(described_class.new(orientation: :vertical))

    expect(page).to have_css(".panel-separator[role='separator'][aria-orientation='vertical'][data-orientation='vertical']")
  end

  it "renders a decorative separator without separator semantics" do
    render_inline(described_class.new(decorative: true, aria: { label: "Ignored visually" }))

    expect(page).to have_css(".panel-separator[aria-hidden='true'][aria-label='Ignored visually']")
    expect(page).to have_no_css(".panel-separator[role='separator']")
  end

  it "falls back to horizontal orientation" do
    render_inline(described_class.new(orientation: :diagonal))

    expect(page).to have_css(".panel-separator[data-orientation='horizontal']")
  end
end
