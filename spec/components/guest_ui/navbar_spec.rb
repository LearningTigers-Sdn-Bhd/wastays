# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::Navbar, type: :component do
  let(:items) do
    [
      GuestUI::NavItem.new(label: "Home", path: "/guest/dashboard", icon: "house", active: true),
      GuestUI::NavItem.new(label: "Bookings", path: "/guest/bookings", icon: "calendar-days")
    ]
  end

  it "links every destination and marks the current one" do
    render_inline(described_class.new(items:, title: "Home"))

    expect(page).to have_css("nav.guest-navbar__nav a.guest-navbar__link", count: 2)
    expect(page).to have_css("a.guest-navbar__link[aria-current='page'][href='/guest/dashboard']", text: "Home")
    expect(page).to have_no_css("a.guest-navbar__link[href='/guest/bookings'][aria-current]")
  end

  it "names the page for a phone" do
    render_inline(described_class.new(items:, title: "WS-123"))

    expect(page).to have_css(".guest-navbar__title", text: "WS-123")
    expect(page).to have_no_css("img")
  end

  it "gives the way back when there is one" do
    render_inline(described_class.new(title: "WS-123", back_path: "/guest/bookings"))

    expect(page).to have_css("a.guest-navbar__back[href='/guest/bookings'][aria-label='Back']")
  end

  it "renders the actions slot" do
    render_inline(described_class.new(items:, title: "Home")) do |navbar|
      navbar.with_actions { "Account" }
    end

    expect(page).to have_css(".guest-navbar__actions", text: "Account")
  end
end
