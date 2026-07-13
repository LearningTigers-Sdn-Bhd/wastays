# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::AttachmentGroup, type: :component do
  it "renders a semantic list with the selected layout" do
    render_inline(described_class.new(layout: :grid, aria: { label: "Selected files" })) { "Files" }

    expect(page).to have_css(".panel-attachment-group[role='list'][data-layout='grid'][aria-label='Selected files']", text: "Files")
  end

  it "falls back unknown layouts to a list" do
    render_inline(described_class.new(layout: :tiles)) { "Files" }

    expect(page).to have_css(".panel-attachment-group[data-layout='list']")
  end
end
