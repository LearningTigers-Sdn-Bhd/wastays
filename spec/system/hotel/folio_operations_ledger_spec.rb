require "rails_helper"

RSpec.describe "Folio Operations ledger", type: :system, js: true do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "hotel_staff", email: "folio-operations@example.com") }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:role) { create(:role, account: account, slug: "front_desk", name: "Front Desk") }
  let(:booking) { create(:booking, hotel: hotel) }

  before do
    driven_by(:cuprite)
    role.permissions << Permission.find_or_create_by!(slug: "view_bookings") { |permission| permission.name = "View bookings" }
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    folio = create(:booking_folio, booking: booking, hotel: hotel, is_primary: true)
    create(:folio_transaction, booking_folio: folio, amount: 50, description: "Posted room charge")
    create(:folio_forecasted_charge, booking_folio: folio, amount: 30, stay_date: Date.current, charge_kind: "accommodation")
    sign_in_through_ui(user)
  end

  it "expands and collapses upcoming charges while posted entries remain visible" do
    visit hotel_booking_control_panel_path(hotel, booking, tab: "folio_operations")

    trigger = find('[data-folio-ledger-section-param="forecasted"]')
    expect(trigger["aria-expanded"]).to eq("false")
    expect(page).to have_css("tr[data-section='forecasted'].hidden", visible: :all)

    trigger.click

    expect(trigger["aria-expanded"]).to eq("true")
    expect(trigger).to have_text("▾")
    expect(page).to have_css("tr[data-section='forecasted']", visible: :visible)

    trigger.click

    expect(trigger["aria-expanded"]).to eq("false")
    expect(trigger).to have_text("▸")
    expect(page).to have_css("tr[data-section='forecasted'].hidden", visible: :all)
    expect(page).to have_css("tr[data-section='posted']", visible: :visible)
  end
end
