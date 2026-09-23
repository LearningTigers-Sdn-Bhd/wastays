# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::EmptyState, type: :component do
  it "says why the list is empty and what to do next" do
    render_inline(described_class.new(icon: "search-x", title: "No bookings match", description: "Try another search.")) do |empty|
      empty.with_action { "Clear filters" }
    end

    expect(page).to have_css(".guest-empty-state .guest-empty-state__icon svg[aria-hidden='true']")
    expect(page).to have_css(".guest-empty-state__title", text: "No bookings match")
    expect(page).to have_css(".guest-empty-state__description", text: "Try another search.")
    expect(page).to have_css(".guest-empty-state__action", text: "Clear filters")
  end

  it "leaves out the parts it was not given" do
    render_inline(described_class.new(icon: "receipt", title: "Nothing here"))

    expect(page).to have_no_css(".guest-empty-state__description, .guest-empty-state__action")
  end
end
