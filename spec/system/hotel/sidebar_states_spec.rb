# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel sidebar navigation states", type: :system do
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, account: account, plan: plan, status: "approved") }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:role) { create(:role, account: account) }

  before do
    driven_by(:rack_test)

    permission = Permission.find_by(slug: "view_reports") ||
      create(:permission, name: "View Reports", slug: "view_reports")
    create(:role_permission, role: role, permission: permission)
    create(:user_hotel_access, user: user, hotel: hotel, role: role)

    sign_in_through_ui(user)
  end

  it "keeps the expanded group subtle while strongly styling its active child" do
    visit hotel_reports_path(hotel)

    within("#hotel-sidebar") do
      expect(page).to have_css("details.sidebar-group-active[open]")
      expect(page).to have_css("summary.sidebar-group-parent", text: "Financial")
      expect(page).to have_no_css("summary.sidebar-nav-link-active", visible: :all)
      expect(page).to have_css("a.sidebar-child-link.sidebar-nav-link-active", text: "Summary")
    end
  end
end
