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
      expect(page).to have_css("a.sidebar-nav-link-active[data-sidebar-route]", text: "Dashboard")
    end

    expect(page).to have_css("#guest-sidebar[data-turbo-permanent]")

    within("#guest-sidebar-mobile", visible: :all) do
      expect(page).to have_link("Dashboard", href: guest_dashboard_path, visible: :all)
      expect(page).to have_link("My Bookings", href: guest_bookings_path, visible: :all)
      expect(page).to have_link("Refunds", href: guest_refund_requests_path, visible: :all)
    end

    expect(page).to have_css("[data-controller='breadcrumb-dropdown']", text: "My Account")
  end
end
