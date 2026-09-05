# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::BulkActionBar, type: :component do
  it "starts hidden and names the selection with its noun" do
    render_inline(described_class.new(noun: "guest"))

    expect(page).to have_css("div.hidden[role='region'][aria-label='Bulk actions']")
    expect(page).to have_css("[data-bulk-select-target='banner']")
    expect(page).to have_css("[data-bulk-select-target='count']", text: "0 guests selected")
  end

  it "offers a way to clear the selection" do
    render_inline(described_class.new)

    expect(page).to have_css("[data-action='bulk-select#clear'][aria-label='Clear selection']")
  end

  it "renders no divider until it has actions" do
    render_inline(described_class.new)
    expect(page).not_to have_css("[aria-hidden='true'].w-px")

    render_inline(described_class.new) do |bar|
      bar.with_action { "<button>Delete</button>".html_safe }
    end
    expect(page).to have_css("[aria-hidden='true'].w-px")
    expect(page).to have_button("Delete")
  end

  it "answers to another controller when the list uses one" do
    render_inline(described_class.new(controller: "board-select", noun: "card"))

    expect(page).to have_css("[data-board-select-target='banner']")
    expect(page).to have_css("[data-board-select-target='count']", text: "0 cards selected")
    expect(page).to have_css("[data-action='board-select#clear']")
  end
end
