# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel sidebar active aliases", type: :system do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:role) { create(:role, account: account) }

  before do
    driven_by(:cuprite)

    permission = Permission.find_by(slug: "manage_hotel_profile") ||
      create(:permission, name: "Manage Hotel Profile", slug: "manage_hotel_profile")
    create(:role_permission, role: role, permission: permission)
    create(:user_hotel_access, user: user, hotel: hotel, role: role)

    sign_in_through_ui(user)
  end

  it "opens settings sidebar mode for setup pages moved into Settings" do
    visit edit_hotel_profile_path(hotel)

    within("#hotel-sidebar") do
      expect(page).to have_link("Back to previous page")
      expect(page).to have_link("Property", href: edit_hotel_profile_path(hotel))
      expect(page).to have_css("a.sidebar-nav-link-active", text: "Property")
    end

    visit hotel_taxes_fees_path(hotel)

    within("#hotel-sidebar") do
      expect(page).to have_link("Back to previous page")
      expect(page).to have_link("Finance", href: hotel_taxes_fees_path(hotel))
      expect(page).to have_css("a.sidebar-nav-link-active", text: "Finance")
    end
  end
end
