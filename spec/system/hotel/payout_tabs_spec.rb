require "rails_helper"

RSpec.describe "Hotel payout tabs", type: :system, js: true do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account, slug: "hotel_owner", name: "Hotel Owner") }

  before do
    driven_by(:cuprite)

    permission = Permission.find_or_create_by!(slug: "view_payouts") { |record| record.name = "View Payouts" }
    RolePermission.find_or_create_by!(role: role, permission: permission)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    create(:payout_batch, hotel: hotel, status: "paid", payout_reference: "PAID-TAB")

    sign_in_through_ui(user)
  end

  it "loads direct tab links and synchronizes switches with the URL and breadcrumb" do
    visit payouts_hotel_reports_path(hotel, tab: "paid")

    expect(page).to have_current_path(payouts_hotel_reports_path(hotel, tab: "paid"))
    expect(page).to have_css("[data-testid='payouts-paid-panel']")
    expect(page).to have_css("[data-testid='payouts-upcoming-panel']", visible: :hidden)
    expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "Paid History")

    click_button "Upcoming & Processing"

    expect(page).to have_current_path(payouts_hotel_reports_path(hotel, tab: "upcoming"))
    expect(page).to have_css("[data-testid='payouts-upcoming-panel']")
    expect(page).to have_css("[data-testid='payouts-paid-panel']", visible: :hidden)
    expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "Upcoming & Processing")
  end

  it "falls back to Upcoming & Processing for an unknown tab" do
    visit payouts_hotel_reports_path(hotel, tab: "unknown")

    expect(page).to have_css("[data-testid='payouts-upcoming-panel']")
    expect(page).to have_css("[data-testid='payouts-paid-panel']", visible: :hidden)
    expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "Upcoming & Processing")
  end

  it "keeps Paid History active after filtering its Turbo Frame" do
    visit payouts_hotel_reports_path(hotel, tab: "paid")
    expect(page).to have_css("[data-testid='payouts-paid-panel']")

    expect(page).to have_css('input[name="paid_date_range"]', visible: :all)
    page.execute_script(<<~JS)
      (() => {
        const picker = document.querySelector('input[name="paid_date_range"]').closest('.panel-date-picker')
        const calendar = picker.querySelector("[data-panels-ui--date-picker-target='calendar']")
        calendar.value = '#{1.month.ago.to_date.iso8601}/#{Date.current.iso8601}'
        calendar.dispatchEvent(new Event('change', { bubbles: true }))
      })()
    JS

    expect(page).to have_css("[data-testid='payouts-paid-panel']")
    expect(page).to have_css("[data-testid='payouts-upcoming-panel']", visible: :hidden)
    expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "Paid History")
    expect(page).to have_content("PAID-TAB")
  end
end
