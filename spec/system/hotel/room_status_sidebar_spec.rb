# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel room status sidebar", type: :system do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "approved") }

  def grant_permission(role, slug)
    permission = Permission.find_by(slug: slug) || create(:permission, slug: slug, name: slug.tr("_", " ").titleize)
    create(:role_permission, role: role, permission: permission)
  end

  def sign_in_with_permissions(*slugs)
    user = create(:user, account: account)
    role = create(:role, account: account)
    slugs.each { |slug| grant_permission(role, slug) }
    create(:user_hotel_access, user: user, hotel: hotel, role: role)

    visit login_path
    fill_in "Email Address", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In to Portal"

    user
  end

  before do
    driven_by(:rack_test)
  end

  it "shows the Room Status link for users with view_room_readiness permission" do
    sign_in_with_permissions("view_room_readiness")

    visit hotel_dashboard_path(hotel)

    expect(page).to have_link("Room Status", href: hotel_room_status_board_path(hotel))
  end

  it "hides the Room Status link for users without room status permissions" do
    sign_in_with_permissions

    visit hotel_dashboard_path(hotel)

    expect(page).to have_no_link("Room Status", href: hotel_room_status_board_path(hotel))
  end

  it "does not show the Room Status link for account-level permissions only" do
    user = sign_in_with_permissions
    account_role = create(:role, account: account)
    grant_permission(account_role, "view_room_readiness")
    create(:user_role, user: user, role: account_role)

    visit hotel_dashboard_path(hotel)

    expect(page).to have_no_link("Room Status", href: hotel_room_status_board_path(hotel))
  end
end
