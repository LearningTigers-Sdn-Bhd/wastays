# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel stay view sidebar", type: :system do
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, account: account, plan: plan, status: "live") }

  def grant_permission(role, slug)
    permission = Permission.find_by(slug: slug) || create(:permission, slug: slug, name: slug.tr("_", " ").titleize)
    create(:role_permission, role: role, permission: permission)
  end

  def sign_in_with_permissions(*slugs)
    user = create(:user, account: account)
    role = create(:role, account: account)
    slugs.each { |slug| grant_permission(role, slug) }
    create(:user_hotel_access, user: user, hotel: hotel, role: role)

    sign_in_through_ui(user)

    user
  end

  before do
    driven_by(:rack_test)
    create(:plan_feature, plan: plan, feature: create(:feature, feature_group: feature_group, slug: "room_status_board"), enabled: true)
  end

  it "shows the Stay View link for users with view_room_readiness permission" do
    sign_in_with_permissions("view_room_readiness")

    visit hotel_dashboard_path(hotel)

    expect(page).to have_link("Stay View", href: hotel_stay_view_path(hotel), visible: :all)
  end

  it "hides the Stay View link for users without stay view permissions" do
    sign_in_with_permissions

    visit hotel_dashboard_path(hotel)

    expect(page).to have_no_link("Stay View", href: hotel_stay_view_path(hotel), visible: :all)
  end

  it "shows the Stay View link for account-level permissions only" do
    user = sign_in_with_permissions
    account_role = create(:role, account: account)
    grant_permission(account_role, "view_room_readiness")
    create(:user_role, user: user, role: account_role)

    visit hotel_dashboard_path(hotel)

    expect(page).to have_link("Stay View", href: hotel_stay_view_path(hotel), visible: :all)
  end
end
