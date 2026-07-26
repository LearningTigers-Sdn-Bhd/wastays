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

  it "shows posted and upcoming charges inline with an Outstanding total" do
    visit hotel_booking_workspace_path(hotel, booking, tab: "folio_operations")

    ledger = find("section[data-testid='folio-ledger']")
    expect(ledger).to have_no_css('[data-folio-ledger-section-param="forecasted"]')
    expect(ledger).to have_text("Posted room charge")
    expect(ledger).to have_text("30.00") # upcoming charge renders inline, not behind a toggle
    expect(ledger).to have_text("MYR 80.00") # Outstanding total = posted 50 + upcoming 30
  end

  it "switches standalone folios and restores the prior selection with browser history" do
    first_folio = booking.booking_folios.first
    second_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, label: "Incidentals Folio")
    visit hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: first_folio.id)

    find("nav[aria-label='Booking folios'] a[href*='folio_id=#{second_folio.id}']").click

    expect(page).to have_current_path(hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: second_folio.id))
    expect(page).to have_css("#folio-operations-panel")
    expect(page).to have_css("nav[aria-label='Booking folios'] a[aria-current='page']", text: second_folio.folio_number.to_s)

    page.go_back

    expect(page).to have_current_path(hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: first_folio.id))
    expect(page).to have_css("nav[aria-label='Booking folios'] a[aria-current='page']", text: first_folio.folio_number.to_s)
  end

  it "closes an eligible folio through the migrated PanelsUI dialog" do
    role.permissions << Permission.find_or_create_by!(slug: "manage_folio_windows") { |permission| permission.name = "Manage folio windows" }
    closable = create(:booking, hotel: hotel)
    folio = create(:booking_folio, booking: closable, hotel: hotel, is_primary: true, label: "Closable Folio")

    visit hotel_booking_workspace_path(hotel, closable, tab: "folio_operations")

    expect(page).to have_no_css("dialog#close-workspace-folio-#{folio.id}[open]")
    click_button "Close"
    expect(page).to have_css("dialog#close-workspace-folio-#{folio.id}[open]")

    within("dialog#close-workspace-folio-#{folio.id}") do
      fill_in "Reason", with: "End of stay"
      click_button "Close Folio"
    end

    expect(page).to have_css("#folio-operations-panel")
    expect(folio.reload).to be_closed
  end

  it "switches to a folio on another group child booking" do
    group = create(:group_booking, hotel: hotel)
    booking.update!(group_booking: group, group_position: 1)
    create(:booking_room, booking: booking, room_number: "101")
    sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
    create(:booking_room, booking: sibling, room_number: "102")
    sibling_folio = create(:booking_folio, booking: sibling, hotel: hotel, label: "Room 102 Folio")
    first_folio = booking.booking_folios.first
    first_path = hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: first_folio.id)
    sibling_path = hotel_booking_workspace_path(hotel, sibling, tab: "folio_operations", folio_id: sibling_folio.id)
    visit first_path

    find("nav[aria-label='Booking folios'] a[href*='folio_id=#{sibling_folio.id}']").click

    expect(page).to have_current_path(sibling_path)
    expect(page).to have_css("#folio-operations-panel")
    expect(page).to have_css("nav[aria-label='Booking folios'] a[aria-current='page']", text: sibling_folio.folio_number.to_s)

    page.go_back
    expect(page).to have_current_path(first_path)
    expect(page).to have_css("nav[aria-label='Booking folios'] a[aria-current='page']", text: first_folio.folio_number.to_s)

    page.go_forward
    expect(page).to have_current_path(sibling_path)
    expect(page).to have_css("nav[aria-label='Booking folios'] a[aria-current='page']", text: sibling_folio.folio_number.to_s)
  end
end
