# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::StatCard, type: :component do
  it "shows the label with its icon, then the number" do
    render_inline(described_class.new(label: "Bookings", value: 12, icon: "calendar-days"))

    expect(page).to have_css(".guest-stat-card .guest-stat-card__label svg[aria-hidden='true']")
    expect(page).to have_css(".guest-stat-card__label", text: "Bookings")
    expect(page).to have_css(".guest-stat-card__value", text: "12")
  end
end
