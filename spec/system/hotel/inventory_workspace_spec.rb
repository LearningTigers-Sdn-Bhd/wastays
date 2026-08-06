require "rails_helper"

RSpec.describe "Hotel inventory calendar", type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin", email: "inventory@example.com") }
  let(:hotel) { create(:hotel, account: account, status: "approved", default_currency: "MYR") }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }
  let!(:room_type) { create(:room_type, hotel: hotel, name: "Twin Room", quantity: 4, base_price: 180, room_numbers: %w[201 202 203 204]) }
  let!(:rate_plan) { create(:rate_plan, room_type: room_type, name: "Best Available Rate") }

  before do
    driven_by(:rack_test)

    [
      "manage_guest_arrival", "view_bookings", "manage_room_status", "manage_requests",
      "manage_hotel_profile", "manage_users", "view_reports", "view_payouts", "view_audit_logs",
      "manage_night_audit"
    ].each do |slug|
      permission = Permission.find_by(slug: slug) || create(:permission, name: slug.titleize, slug: slug)
      role.permissions << permission unless role.permissions.include?(permission)
    end

    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    sign_in_through_ui(user)
  end

  it "renders the PMS calendar views and persisted ARI values" do
    create(:room_inventory, room_type: room_type, date: Date.current, quantity: 2, status: "open")
    create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: Date.current, price: 333, currency: "MYR", min_stay: 2, stop_sell: true)

    visit hotel_inventory_index_path(hotel, start_date: Date.current)
    expect(page).to have_content("Rates & Availability")
    expect(page).to have_css("[data-testid='availability-cell-#{room_type.id}-#{Date.current}']", text: "2")
    expect(page).to have_css("[data-testid='rate-cell-#{room_type.id}-#{rate_plan.id}-#{Date.current}']", text: "333.00")
    expect(page).to have_css("[data-testid='rate-cell-#{room_type.id}-#{rate_plan.id}-#{Date.current}']", text: "MIN2")
    expect(page).to have_css("[data-testid='rate-cell-#{room_type.id}-#{rate_plan.id}-#{Date.current}']", text: "STOP")
  end
end
