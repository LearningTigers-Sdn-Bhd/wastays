require "rails_helper"

RSpec.describe "Guest navigation shell", type: :system do
  let(:guest) { create(:guest, name: "Aisha Rahman") }

  before do
    driven_by(:rack_test)

    token = guest.generate_magic_token!
    visit guest_verify_path(token: token)
  end

  it "renders shared desktop and mobile navigation with active state" do
    visit guest_dashboard_path

    within("#guest-sidebar") do
      expect(page).to have_link("Dashboard", href: guest_dashboard_path)
      expect(page).to have_link("My Bookings", href: guest_bookings_path)
      expect(page).to have_link("Refunds", href: guest_refund_requests_path)
      expect(page).to have_text("Aisha Rahman")
      expect(page).to have_css("a.panel-sidebar__link[data-sidebar-route][aria-current='page']", text: "Dashboard")
    end

    expect(page).to have_css(
      "#guest-sidebar[data-turbo-permanent][data-controller~='panels-ui--sidebar'][data-panels-ui--sidebar-key-value='guest']"
    )
    expect(page).to have_css("header.panel-navbar[data-sticky='true']")
    expect(page).to have_css("#guest-profile[data-controller='panels-ui--dropdown-menu']")
    expect(page).to have_css("button[command='show-modal'][commandfor='guest-sidebar-mobile']")

    within("#guest-sidebar-mobile", visible: :all) do
      expect(page).to have_link("Dashboard", href: guest_dashboard_path, visible: :all)
      expect(page).to have_link("My Bookings", href: guest_bookings_path, visible: :all)
      expect(page).to have_link("Refunds", href: guest_refund_requests_path, visible: :all)
    end

    expect(page).to have_css("#guest-breadcrumb[data-controller='panels-ui--breadcrumb']", text: "My Account")
  end
end
