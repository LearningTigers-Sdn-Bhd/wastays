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
    visit hotel_booking_workspace_path(hotel, booking, tab: "folio_operations")

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

  it "switches standalone folios and restores the prior selection with browser history" do
    first_folio = booking.booking_folios.first
    second_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, name: "Incidentals Folio")
    visit hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: first_folio.id)

    within('nav[aria-label="Booking folios"]') { click_link "Incidentals Folio" }

    expect(page).to have_current_path(hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: second_folio.id))
    expect(page).to have_css("#folio-operations-heading", text: "Incidentals Folio")
    expect(page).to have_css("nav[aria-label='Booking folios'] a[aria-current='page']", text: "Incidentals Folio")

    page.go_back

    expect(page).to have_current_path(hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: first_folio.id))
    expect(page).to have_css("nav[aria-label='Booking folios'] a[aria-current='page']", text: first_folio.display_name)
  end

  it "switches to a folio on another group child booking" do
    group = create(:group_booking, hotel: hotel)
    booking.update!(group_booking: group, group_position: 1)
    create(:booking_room, booking: booking, room_number: "101")
    sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
    create(:booking_room, booking: sibling, room_number: "102")
    sibling_folio = create(:booking_folio, booking: sibling, hotel: hotel, name: "Room 102 Folio")
    first_folio = booking.booking_folios.first
    first_path = hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: first_folio.id)
    sibling_path = hotel_booking_workspace_path(hotel, sibling, tab: "folio_operations", folio_id: sibling_folio.id)
    visit first_path

    within('nav[aria-label="Bookings and folios"]') { click_link "Room 102 Folio" }

    expect(page).to have_current_path(sibling_path)
    expect(page).to have_css("#folio-operations-heading", text: "Room 102 Folio")
    expect(page).to have_content("Room 102 · Booking #{sibling.formatted_reservation_number}")
    expect(page).to have_css("nav[aria-label='Bookings and folios'] a[aria-current='page']", text: "Room 102 Folio")

    page.go_back
    expect(page).to have_current_path(first_path)
    expect(page).to have_css("nav[aria-label='Bookings and folios'] a[aria-current='page']", text: first_folio.display_name)

    page.go_forward
    expect(page).to have_current_path(sibling_path)
    expect(page).to have_css("nav[aria-label='Bookings and folios'] a[aria-current='page']", text: "Room 102 Folio")
  end
end
