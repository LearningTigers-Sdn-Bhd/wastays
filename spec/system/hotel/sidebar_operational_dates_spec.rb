# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel sidebar operational dates", type: :system do
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:hotel) do
    create(
      :hotel,
      account: account,
      plan: plan,
      status: "live",
      time_zone: "Kuala Lumpur",
      accounting_business_date: Date.new(2026, 9, 14)
    )
  end
  let(:user) { create(:user, account: account, role: "admin") }
  let(:role) { create(:role, account: account) }

  before do
    driven_by(:rack_test)
    %w[manage_guest_arrival view_reports view_bookings manage_hotel_profile manage_account].each do |slug|
      permission = Permission.find_by(slug: slug) || create(:permission, name: slug.tr("_", " ").titleize, slug: slug)
      create(:role_permission, role: role, permission: permission)
    end
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_through_ui(user)
  end

  it "shows the dates in every Hotel Portal sidebar layer" do
    travel_to(Time.utc(2026, 9, 14, 16, 30)) do
      {
        hotel_dashboard_path(hotel) => "#hotel-sidebar",
        hotel_reports_path(hotel) => "#hotel-reports-sidebar",
        hotel_folios_path(hotel) => "#hotel-financials-sidebar",
        hotel_general_settings_path(hotel) => "#hotel-settings-sidebar"
      }.each do |path, sidebar|
        visit path

        within(sidebar) do
          expect(page).to have_css(".panel-sidebar__details.panel-sidebar__presentation--expanded", visible: :all)
          expect(page).to have_css("dt", text: "Working Date", visible: :all)
          expect(page).to have_css("time[datetime='2026-09-14']", text: "14 Sep 2026", visible: :all)
          expect(page).to have_css("dt", text: "System Date", visible: :all)
          expect(page).to have_css("time[datetime='2026-09-15']", text: "15 Sep 2026", visible: :all)
        end
      end
    end
  end
end
