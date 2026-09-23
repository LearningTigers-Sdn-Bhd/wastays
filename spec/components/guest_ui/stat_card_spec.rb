# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::StatCard, type: :component do
  it "shows its icon, the number, and the label in its tone" do
    render_inline(described_class.new(label: "Bookings", value: 12, icon: "calendar-days", tone: :info))

    expect(page).to have_css(".guest-stat-card[data-tone='info'] .guest-stat-card__icon svg[aria-hidden='true']")
    expect(page).to have_css(".guest-stat-card__label", text: "Bookings")
    expect(page).to have_css(".guest-stat-card__value", text: "12")
  end

  it "falls back to muted for an unknown tone" do
    render_inline(described_class.new(label: "Odd", value: 1, icon: "circle", tone: :purple))

    expect(page).to have_css(".guest-stat-card[data-tone='muted']")
  end
end
