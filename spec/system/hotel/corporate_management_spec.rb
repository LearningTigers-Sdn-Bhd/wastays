# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel corporate management", type: :system, js: true do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account) }
  let(:user) { create(:user, account: account) }
  let(:role) { create(:role, account: account) }
  let(:permission) do
    Permission.find_or_create_by!(slug: "manage_corporate_accounts") do |record|
      record.name = "Manage Corporate Accounts"
    end
  end

  before do
    driven_by(:cuprite)
    role.permissions << permission
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_through_ui(user)
  end

  it "opens, validates, cancels, and completes invitations in the offcanvas" do
    create(:user, email: "staff@example.com")
    visit hotel_corporate_accounts_path(hotel)

    expect(page).to have_content("Corporate Management")
    expect(page).to have_link("Corporate Managements")

    click_link "Invite corporate account"
    expect(page).to have_css("turbo-frame#offcanvas_drawer", text: "Invite corporate account")
    expect(page).to have_no_field("Company name")

    within("#offcanvas_drawer") do
      cancel_button = find("button[type='button']", text: "Cancel", exact_text: true)
      execute_script("arguments[0].click()", cancel_button)
    end
    expect(page).to have_css("#offcanvas_drawer_container.hidden", visible: :all, wait: 2)

    click_link "Invite corporate account"
    within("#offcanvas_drawer") do
      fill_in "Corporate contact email", with: "staff@example.com"
      fill_in "Corporate type", with: "agency"
      select "Direct bill", from: "Relationship"
      click_button "Send invitation"
    end

    within("#offcanvas_drawer") do
      expect(page).to have_content("hotel staff")
      expect(page).to have_field("Corporate contact email", with: "staff@example.com")
      expect(page).to have_field("Corporate type", with: "agency")

      fill_in "Corporate contact email", with: "billing@example.com"
      click_button "Send invitation"
    end

    expect(page).to have_css("#offcanvas_drawer_container.hidden", visible: :all, wait: 3)
    expect(page).to have_content("billing@example.com")
    expect(CorporateInvitation.find_by!(email: "billing@example.com").relationship_type).to eq("direct_bill")
  end
end
