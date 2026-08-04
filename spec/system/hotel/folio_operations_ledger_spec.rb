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

  it "closes an eligible folio through the folio-action Sheet" do
    role.permissions << Permission.find_or_create_by!(slug: "manage_folio_windows") { |permission| permission.name = "Manage folio windows" }
    closable = create(:booking, hotel: hotel)
    folio = create(:booking_folio, booking: closable, hotel: hotel, is_primary: true, label: "Closable Folio")

    visit hotel_booking_workspace_path(hotel, closable, tab: "folio_operations")

    expect(page).to have_no_css("dialog#folio-close-window-sheet")
    click_link "Close"
    expect(page).to have_css("turbo-frame#folio_action_sheet dialog#folio-close-window-sheet[open]")

    within("dialog#folio-close-window-sheet") do
      fill_in "Reason", with: "End of stay"
      click_button "Close folio"
    end

    expect(page).to have_css("#folio-operations-panel")
    expect(folio.reload).to be_closed
  end

  it "edits a folio window through the folio-action Sheet" do
    role.permissions << Permission.find_or_create_by!(slug: "manage_folio_windows") { |permission| permission.name = "Manage folio windows" }
    folio = booking.booking_folios.first

    visit hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: folio.id)

    click_link "Edit"

    expect(page).to have_css("turbo-frame#folio_action_sheet dialog#folio-window-sheet[open]")

    within("dialog#folio-window-sheet") do
      fill_in "Label", with: "Renamed Folio"
      click_button "Save changes"
    end

    expect(page).to have_css("#folio-operations-panel")
    expect(folio.reload.label).to eq("Renamed Folio")
  end

  # A guest or house folio has no payer choice, so the payer field hides and a
  # hidden input carries the locked value.
  it "locks the payer to the folio type while editing a folio window" do
    role.permissions << Permission.find_or_create_by!(slug: "manage_folio_windows") { |permission| permission.name = "Manage folio windows" }
    folio = booking.booking_folios.first
    expect(folio.folio_type).to eq("guest")

    visit hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: folio.id)
    click_link "Edit"
    expect(page).to have_css("dialog#folio-window-sheet[open]")

    within("dialog#folio-window-sheet") do
      # Guest folios lock the payer, so the field is hidden on connect.
      expect(page).to have_no_css("[data-folio-window-payer-target='payerType']", visible: :visible)

      find("[data-folio-window-payer-target='folioType'] [data-controller~='panels-ui--select-menu'] button").click
      find("[role='option']", text: "House").click

      expect(page).to have_no_css("[data-folio-window-payer-target='payerType']", visible: :visible)
      click_button "Save changes"
    end

    expect(page).to have_css("#folio-operations-panel")
    expect(folio.reload).to have_attributes(folio_type: "house", payer_type: "hotel")
  end

  it "posts a cash payment through the folio-action Sheet" do
    role.permissions << Permission.find_or_create_by!(slug: "post_folio_payments") { |permission| permission.name = "Post folio payments" }
    folio = booking.booking_folios.first

    visit hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: folio.id)

    click_link "Add Payment"

    expect(page).to have_css("turbo-frame#folio_action_sheet dialog#folio-post-transaction-sheet[open]")

    within("dialog#folio-post-transaction-sheet") do
      find("[data-controller~='panels-ui--select-menu'] button").click
      find("[role='option']", text: "Cash").click
      fill_in "Amount", with: "40.00"
      fill_in "Description", with: "Front desk cash"
      click_button "Post payment"
    end

    expect(page).to have_css("#folio-operations-panel")
    expect(folio.folio_transactions.payment.where(category: "cash")).to exist
  end

  it "keeps an allowed per-item amount override while typing and posts it" do
    role.permissions << Permission.find_or_create_by!(slug: "post_folio_charges") { |permission| permission.name = "Post folio charges" }
    folio = booking.booking_folios.first
    extra_charge = create(:hotel_extra_charge, hotel: hotel, pricing_type: "fixed", rate_value: 5,
      charging_unit: "per_item", allow_amount_override: true)

    visit hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: folio.id)
    click_link "Add Charge"

    expect(page).to have_css("turbo-frame#folio_action_sheet dialog#folio-post-transaction-sheet[open]")
    within("dialog#folio-post-transaction-sheet") do
      find("[data-controller~='panels-ui--select-menu'] button").click
      find("[role='option']", text: extra_charge.name).click
      fill_in "Quantity", with: "2"
      expect(page).to have_field("Amount", with: "10.00", readonly: false)

      fill_in "Amount", with: "8.00"
      expect(page).to have_field("Amount", with: "8.00", readonly: false)
      click_button "Add charge"
    end

    expect(page).to have_css("#folio-operations-panel")
    expect(folio.folio_transactions.where(transaction_code: extra_charge.transaction_code).order(:id).last).to have_attributes(
      amount: 8.to_d,
      description: "#{extra_charge.name} · 2 × MYR 5.00 · override MYR 8.00"
    )
  end

  it "moves a posted charge through the folio-action Sheet" do
    role.permissions << Permission.find_or_create_by!(slug: "manage_folio_movements") { |permission| permission.name = "Manage folio movements" }
    source_folio = booking.booking_folios.first
    target_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, label: "Company Folio")
    transaction = source_folio.folio_transactions.first

    visit hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: source_folio.id)

    find("#folio-row-actions-#{transaction.id} button").click
    click_link "Move"

    expect(page).to have_css("turbo-frame#folio_action_sheet dialog#folio-move-transaction-sheet[open]")

    within("dialog#folio-move-transaction-sheet") do
      find("[data-controller~='panels-ui--select-menu'] button").click
      find("[role='option']", text: "Company Folio").click
      fill_in "Reason", with: "Company settles the room"
      click_button "Move transaction"
    end

    expect(page).to have_css("#folio-operations-panel")
    expect(target_folio.folio_transactions.charge.where(moved_from_transaction: transaction)).to exist
  end

  it "reverses a posted charge through the folio-action Sheet" do
    role.permissions << Permission.find_or_create_by!(slug: "post_folio_corrections") { |permission| permission.name = "Post folio corrections" }
    folio = booking.booking_folios.first
    transaction = folio.folio_transactions.first

    visit hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: folio.id)

    find("#folio-row-actions-#{transaction.id} button").click
    click_link "Reverse"

    expect(page).to have_css("turbo-frame#folio_action_sheet dialog#folio-reverse-transaction-sheet[open]")

    within("dialog#folio-reverse-transaction-sheet") do
      fill_in "Reason", with: "Posting error"
      fill_in "Note", with: "Charged to the wrong booking"
      click_button "Reverse"
    end

    expect(page).to have_css("#folio-operations-panel")
    expect(transaction.reload.voided_by_transaction).to be_present
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
