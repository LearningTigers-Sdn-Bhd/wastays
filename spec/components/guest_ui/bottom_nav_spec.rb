# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::BottomNav, type: :component do
  let(:items) do
    [
      GuestUI::NavItem.new(label: "Home", path: "/guest/dashboard", icon: "house"),
      GuestUI::NavItem.new(label: "Bookings", path: "/guest/bookings", icon: "calendar-days", active: true),
      GuestUI::NavItem.new(label: "Refunds", path: "/guest/refund_requests", icon: "receipt")
    ]
  end

  it "draws one tab for each destination and marks the current one" do
    render_inline(described_class.new(items:))

    expect(page).to have_css("nav.guest-bottom-nav[aria-label='Guest portal'] a.guest-bottom-nav__link", count: 3)
    expect(page).to have_css("a[aria-current='page'][href='/guest/bookings']", text: "Bookings")
    expect(page.all("a[aria-current]").size).to eq(1)
  end

  it "draws nothing without destinations" do
    render_inline(described_class.new(items: []))

    expect(page).to have_no_css("nav")
  end
end
