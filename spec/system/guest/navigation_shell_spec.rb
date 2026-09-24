require "rails_helper"

RSpec.describe "Guest navigation shell", type: :system do
  let(:guest) { create(:guest, name: "Aisha Rahman") }

  before do
    driven_by(:rack_test)

    token = guest.generate_magic_token!
    visit guest_verify_path(token: token)
  end

  it "renders the navbar and the bottom nav with the same destinations" do
    visit guest_dashboard_path

    within("header.guest-navbar") do
      expect(page).to have_css(".guest-navbar__title", text: "Home")
      expect(page).to have_css("a.guest-navbar__link[aria-current='page']", text: "Home")
      expect(page).to have_link("Bookings", href: guest_bookings_path)
      expect(page).to have_link("Refunds", href: guest_refund_requests_path)
      expect(page).to have_text("Aisha Rahman")
      expect(page).to have_css("#guest-account-list [role='menuitem']", text: "Sign out", visible: :all)
    end

    within("nav.guest-bottom-nav") do
      expect(page).to have_css("a[aria-current='page'][href='#{guest_dashboard_path}']", text: "Home")
      expect(page).to have_link("Bookings", href: guest_bookings_path)
      expect(page).to have_link("Refunds", href: guest_refund_requests_path)
    end

    expect(page).to have_no_css("#guest-sidebar, #guest-breadcrumb, .panel-navbar")
  end
end
