# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel sidebar active aliases", type: :system do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "live") }
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

  it "uses the settings sidebar for setup pages moved into Settings" do
    visit edit_hotel_profile_path(hotel)

    within("#hotel-settings-sidebar") do
      expect(page).to have_no_link("Back to previous page")
      expect(page).to have_link("Property", href: edit_hotel_profile_path(hotel))
      expect(page).to have_css("a.panel-sidebar__link[aria-current='page']", text: "Property")
    end

    visit hotel_taxes_fees_path(hotel)

    within("#hotel-settings-sidebar") do
      expect(page).to have_no_link("Back to previous page")
      expect(page).to have_css("button.panel-sidebar__group-trigger[aria-label='Commercial']", visible: :all)
      expect(page).to have_link("Taxes & Fees", href: hotel_taxes_fees_path(hotel), visible: :all)
      expect(page).to have_css("a.panel-sidebar__child[aria-current='page']", text: "Taxes & Fees", visible: :all)
    end
  end
end
