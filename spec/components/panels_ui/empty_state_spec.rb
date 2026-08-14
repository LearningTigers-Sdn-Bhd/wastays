# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::EmptyState, type: :component do
  it "states what is missing, with a decorative icon" do
    render_inline(described_class.new(title: "No photos yet", description: "Add the ones that show the property best."))

    expect(page).to have_css(".panel-empty-state .panel-empty-state__title", text: "No photos yet")
    expect(page).to have_css(".panel-empty-state__description", text: "Add the ones that show the property best.")
    expect(page).to have_css(".panel-empty-state__icon[aria-hidden='true'] svg")
  end

  it "carries the action that fills the region" do
    render_inline(described_class.new(title: "No rooms yet")) do |state|
      state.with_action { '<button type="button">Add room</button>'.html_safe }
    end

    expect(page).to have_css(".panel-empty-state__action button", text: "Add room")
  end

  it "omits the description, the action, and a suppressed icon" do
    render_inline(described_class.new(title: "Nothing here", icon: nil))

    expect(page).to have_css(".panel-empty-state__title", text: "Nothing here")
    expect(page).to have_no_css(".panel-empty-state__description")
    expect(page).to have_no_css(".panel-empty-state__action")
    expect(page).to have_no_css(".panel-empty-state__icon")
  end

  it "merges caller classes and attributes onto the root" do
    render_inline(described_class.new(title: "Empty", class: "border-t", id: "album-empty", data: { testid: "empty" }))

    expect(page).to have_css("#album-empty.panel-empty-state.border-t[data-testid='empty']")
  end
end
