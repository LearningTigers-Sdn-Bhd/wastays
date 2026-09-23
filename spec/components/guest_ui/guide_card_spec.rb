# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::GuideCard, type: :component do
  it "shows the icon, the title, the first fact, the body, and an action" do
    render_inline(described_class.new(title: "Directions", icon: "map", subtitle: "20 min from the airport",
                                      action: { label: "Open in Maps", href: "https://maps.example/x", icon: "navigation", new_tab: true })) do
      "Take exit 14."
    end

    expect(page).to have_css("article.guest-guide-card h3", text: "Directions")
    expect(page).to have_css(".guest-guide-icon svg[aria-hidden='true']")
    expect(page).to have_css(".guest-guide-card__subtitle", text: "20 min from the airport")
    expect(page).to have_css(".guest-guide-card__body", text: "Take exit 14.")
    expect(page).to have_css(".guest-guide-card__action a[href='https://maps.example/x'][target='_blank'][rel='noopener']",
                             text: "Open in Maps")
  end

  it "draws nothing with no body and no subtitle" do
    render_inline(described_class.new(title: "Arrival"))

    expect(page).to have_no_css("article")
  end
end
