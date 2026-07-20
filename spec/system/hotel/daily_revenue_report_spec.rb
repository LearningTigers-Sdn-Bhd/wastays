require "rails_helper"

RSpec.describe "Daily revenue transaction register", type: :system, js: true do
  let(:plan) { create(:plan) }
  let(:hotel) { create(:hotel, plan: plan) }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account, slug: "hotel_owner", name: "Hotel Owner") }
  let(:today) { Time.current.in_time_zone(hotel.hotel_time_zone).to_date }

  before do
    driven_by(:cuprite)

    permission = Permission.find_or_create_by!(slug: "view_reports") { |record| record.name = "View Reports" }
    RolePermission.find_or_create_by!(role: role, permission: permission)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    feature = create(:feature, feature_group: create(:feature_group), slug: "revenue_allocation_per_night")
    create(:plan_feature, plan: plan, feature: feature, enabled: true)

    booking = create(:booking, hotel: hotel, guest_name: "Sunset Guest")
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    code = create(:transaction_code, hotel: hotel, code: "ISLAND_HOP", name: "Island Hopping", kind: "charge", category: "other")
    original = create(:folio_transaction, booking_folio: folio, transaction_code: code, category: "other", amount: 150, posting_date: today)
    reversal = create(:folio_transaction, booking_folio: folio, transaction_type: "adjustment", category: "correction",
      amount: -150, posting_date: today, reversal_of_transaction: original)
    original.update_column(:voided_by_transaction_id, reversal.id)

    sign_in_through_ui(user)
  end

  it "switches to the Transactions tab and shows every posted transaction with reversal state as text" do
    visit daily_revenue_hotel_reports_path(hotel, date_preset: "today")

    expect(page).to have_link("Overview")
    click_link "Transactions"

    expect(page).to have_current_path(%r{tab=transactions})
    expect(page).to have_css("table thead th", text: /status/i)
    expect(page).to have_css('[data-testid="daily-revenue-transaction-row"]', count: 2)
    expect(page).to have_content("Island Hopping")
    expect(page).to have_content("Reversed")
    expect(page).to have_content("Reversal")
    expect(page).to have_link(href: /booking-control-panels/)
  end
end
