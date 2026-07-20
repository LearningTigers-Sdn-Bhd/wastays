require "rails_helper"

RSpec.describe "Daily Report: Revenue vs Cashier Sales", type: :system, js: true do
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

    booking = create(:booking, hotel: hotel, guest_name: "Sunset Guest", check_in: today - 2.days, check_out: today)
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    create(:folio_transaction, booking_folio: folio, transaction_code: room_code, category: "accommodation", amount: 75, posting_date: today - 2.days, metadata: { stay_date: today - 2.days })
    create(:folio_transaction, booking_folio: folio, transaction_code: room_code, category: "accommodation", amount: 75, posting_date: today - 1.day, metadata: { stay_date: today - 1.day })
    create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount: 150, posting_date: today)

    sign_in_through_ui(user)
  end

  it "shows multi-night accrual charges on their stay dates and payment on its cash-movement date" do
    visit daily_report_hotel_reports_path(hotel, start_date: today - 2.days, end_date: today)
    expect(page).to have_content("Daily Report")

    click_link "Revenue"
    expect(page).to have_current_path(%r{tab=revenue})
    expect(page).to have_content("Room Revenue")
    expect(page).to have_css('[data-testid="charge-register-row"]', count: 2)
    expect(page).to have_content((today - 2.days).strftime("%d %b %Y"))
    expect(page).to have_content((today - 1.day).strftime("%d %b %Y"))

    click_link "Cashier Sales"
    expect(page).to have_current_path(%r{tab=cashier})
    expect(page).to have_content("Settlement")
    expect(page).to have_css('[data-testid="settlement-row"]', count: 1)
    expect(page).to have_content("Sunset Guest")
    expect(page).to have_content(today.strftime("%d %b %Y"))
  end
end
