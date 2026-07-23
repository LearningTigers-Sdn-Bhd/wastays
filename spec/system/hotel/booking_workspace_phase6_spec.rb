# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Booking workspace Phase 6", :business_day, type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "hotel_staff", email: "phase6@example.com") }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:role) { create(:role, account: account, slug: "front_desk", name: "Front Desk") }
  let(:booking) { create(:booking, hotel: hotel) }

  before do |example|
    driven_by(example.metadata[:js] ? :cuprite : :rack_test)
    %w[view_bookings manage_bookings].each do |slug|
      role.permissions << Permission.find_or_create_by!(slug: slug) { |record| record.name = slug.humanize }
    end
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    create(:booking_room, booking: booking)
    guest = create(:guest, email: "hanami@mail.com", phone: "+60123451234", government_id: "P4821")
    create(:booking_guest, booking: booking, guest: guest, is_primary: true)
    folio = create(:booking_folio, booking: booking, hotel: hotel, is_primary: true)
    create(:deposit, booking: booking, hotel: hotel, booking_folio: folio, amount: 175, status: "held")
    create(:housekeeping_request, booking: booking, request_details: "Fresh towels", status: "pending")
    create(:complaint_request, booking: booking, complaint_details: "Noisy hallway", status: "pending")

    visit login_path
    fill_in "Email Address", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In to Portal"
  end

  it "uses contextual rails while navigating the core Phase 6 tabs" do
    visit hotel_booking_workspace_path(hotel, booking, tab: "room_and_rate")
    expect(page).to have_css('[data-layout-mode="standard"]')
    expect(page).to have_content("Room & Rate")

    click_link "Guest Details"
    expect(page).to have_current_path(hotel_booking_workspace_path(hotel, booking, tab: "guest_details"))
    expect(page).to have_css('[data-layout-mode="entity"]')
    expect(page).to have_content("Primary guest for this room")
    expect(page).to have_field("Email", with: "hanami@mail.com")
    expect(page).to have_content("Guest details recorded for this stay.")
    expect(page).to have_button("Save Guest")

    click_link "Security Deposits"
    expect(page).to have_css('[data-layout-mode="standard"]')
    expect(page).to have_content("Security Deposits")
    expect(page).to have_content("MYR 175.00")

    click_link "Billing Preferences"
    expect(page).to have_css('[data-layout-mode="standard"]')
    expect(page).to have_content("Billing parties")

    click_link "Folio Operations"
    expect(page).to have_css('[data-layout-mode="entity"]')
    expect(page).to have_content("Ledger")
    expect(page).not_to have_content("Manage Folio Windows")

    click_link "Requests"
    expect(page).to have_css('[data-layout-mode="standard"]')
    expect(page).to have_content("Fresh towels")
    expect(page).to have_content("Noisy hallway")
  end

  xit "re-renders the active tab with Turbo frame navigation", js: true do
    visit hotel_booking_workspace_path(hotel, booking, tab: "room_and_rate")

    within("#booking-control-tabs") do
      expect(page).to have_css("a[aria-current='page']", text: "Room & Rate")
      click_link "Guest Details"
    end

    within("#booking-control-tabs") do
      expect(page).to have_css("a[aria-current='page']", text: "Guest Details")
      expect(page).to have_no_css("a[aria-current='page']", text: "Room & Rate")
    end

    expect(page).to have_current_path(hotel_booking_workspace_path(hotel, booking, tab: "guest_details"))
    expect(page).to have_content("Primary guest for this room")
    expect(page).to have_css("#hotel-breadcrumb", text: "Booking Workspace")
    expect(page).to have_no_css("#hotel-breadcrumb [data-tabs-breadcrumb-label]")
  end

  it "opens and keyboard-closes a room-card audit trail Sheet", js: true do
    plan = create(:plan)
    hotel.update!(plan: plan)
    feature = create(:feature, feature_group: create(:feature_group), slug: "full_audit_trail")
    create(:plan_feature, plan: plan, feature: feature, enabled: true)
    create(:booking_audit_log, hotel: hotel, auditable: booking, user: user,
      old_value: { "status" => "pending" }, new_value: { "status" => "confirmed" })

    visit hotel_front_desk_path(hotel, tab: "bookings", view: "rooms", booking_query: booking.confirmation_token)
    trigger = find("button[aria-label='Booking actions']")
    trigger.click
    click_link "Audit trail"

    expect(page).to have_css("dialog#booking-audit-trail-sheet[open]", wait: 3)
    expect(page.evaluate_script("document.querySelector('#booking-audit-trail-sheet').contains(document.activeElement)")).to be(true)
    within("#booking-audit-trail-sheet") do
      expect(page).to have_content("Audit Trail")
      click_in_overlay find("summary", text: "View Changes")
      expect(page).to have_content("Pending")
      expect(page).to have_content("Confirmed")
    end
    page.send_keys(:escape)

    expect(page).to have_no_css("dialog#booking-audit-trail-sheet", wait: 3)
    expect(page).to have_content(booking.confirmation_token)
  end

  it "cancels a booking through the action Sheet from the Actions dropdown", js: true do
    visit hotel_booking_workspace_path(hotel, booking, tab: "booking_details")

    find("button[aria-label='Booking actions']").click
    click_link "Cancel"

    expect(page).to have_css("dialog#booking-cancellation-sheet[open]", wait: 3)
    within("#booking-cancellation-sheet") do
      fill_in "cancellation_reason", with: "Guest cancelled the stay"
      click_in_overlay "Confirm cancellation"
    end

    expect(page).to have_no_css("dialog#booking-cancellation-sheet", wait: 3)
    expect(booking.reload.status).to eq("cancelled")
  end

  it "checks in a booking through the action Sheet", js: true do
    room_type = create(:room_type, hotel: hotel, room_number_mode: "custom", room_numbers: [ "101" ])
    booking.update!(status: "confirmed", check_in: Time.current, check_out: 2.days.from_now)
    booking.booking_rooms.first.update!(room_type: room_type, room_number: "101")
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.current)

    visit hotel_booking_workspace_path(hotel, booking, tab: "booking_details")
    find("button[aria-label='Booking actions']").click
    click_link "Check-in"

    expect(page).to have_css("dialog#booking-check-in-sheet[open]", wait: 3)
    expect(page.evaluate_script("document.querySelector('#booking-check-in-sheet').contains(document.activeElement)")).to be(true)
    within("#booking-check-in-sheet") do
      expect(page).to have_content("Arrival details")
      expect(page).to have_content("Room assignments")
      click_in_overlay "Confirm check-in"
    end

    expect(page).to have_no_css("dialog#booking-check-in-sheet", wait: 3)
    expect(booking.reload.status).to eq("checked_in")
  end

  it "selects and checks in multiple group children with the static action form", js: true do
    room_type = create(:room_type, hotel: hotel, room_number_mode: "custom", room_numbers: %w[101 102])
    group = create(:group_booking, hotel: hotel, name: "Tour Group")
    booking.update!(status: "confirmed", group_booking: group, group_position: 1, guest_name: "First Guest", check_in: Time.current, check_out: 2.days.from_now)
    booking.booking_rooms.first.update!(room_type: room_type, room_number: "101")
    sibling = create(:booking, hotel: hotel, status: "confirmed", group_booking: group, group_position: 2, guest_name: "Second Guest", check_in: booking.check_in, check_out: booking.check_out)
    create(:booking_room, booking: sibling, room_type: room_type, room_number: "102")
    create(:booking_guest, booking: sibling, guest: create(:guest, name: "Second Guest"), is_primary: true)
    create(:booking_folio, booking: sibling, hotel: hotel, is_primary: true)
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.current)

    visit hotel_booking_workspace_path(hotel, booking, tab: "booking_details")
    find("button[aria-label='Booking actions']").click
    click_link "Check-in"

    expect(page).to have_css("dialog#booking-check-in-sheet[open]", wait: 3)
    within("#booking-check-in-sheet") do
      click_in_overlay find("label", text: "Group", match: :first)
      expect(page).to have_checked_field("booking_ids[]", count: 2)
      expect(page).to have_css("[data-group-lifecycle-targets-target='panel']", count: 0)
      expect(page).to have_content("Arrival details")
      expect(page).to have_content("Room assignments")

      click_in_overlay "Confirm check-in"
    end

    expect(page).to have_no_css("dialog#booking-check-in-sheet", wait: 3)
    expect(booking.reload.status).to eq("checked_in")
    expect(sibling.reload.status).to eq("checked_in")
  end

  it "resolves a folio beside its settlement fields and completes checkout", js: true do
    role.permissions << Permission.find_or_create_by!(slug: "post_folio_payments") { |record| record.name = "Post folio payments" }
    booking.update!(check_in: 2.hours.ago, check_out: Time.current)
    booking.update_columns(status: "checkout_required", checked_in_at: 2.hours.ago)
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.current)

    relationship = create(:hotel_corporate_account, :direct_bill, hotel: hotel)
    company_folio = create(
      :booking_folio,
      :secondary,
      booking: booking,
      hotel: hotel,
      name: "Company Folio",
      hotel_corporate_account: relationship
    )
    create(:folio_transaction, booking_folio: company_folio, transaction_type: "charge", amount: 60)

    visit hotel_booking_workspace_path(hotel, booking, tab: "booking_details")
    find("button[aria-label='Booking actions']").click
    click_link "Complete Checkout"

    expect(page).to have_css("dialog#booking-checkout-sheet[open]", wait: 3)
    page.current_window.resize_to(390, 844)
    expect(page.evaluate_script(<<~JS)).to be(true)
      (() => {
        const panel = document.querySelector('#booking-checkout-sheet [data-panels-ui--sheet-target="panel"]')
        return panel.scrollWidth <= panel.clientWidth
      })()
    JS
    page.current_window.resize_to(1400, 1400)

    within("#booking-checkout-sheet") do
      expect(page).to have_content("Resolve folios")
      expect(page).to have_no_content("Settlement Details")

      company_row = find("article", text: "Company Folio")
      resolution_trigger = company_row.find(
        "[data-booking-actions--checkout-settlement-target~='actionControl'] .panel-select-menu__trigger"
      )
      click_in_overlay resolution_trigger
      click_in_overlay find("[role='option']", text: "Pay Now", visible: true)

      within(company_row) do
        expect(page).to have_field("Payment method", with: "cash", visible: :all)
        fill_in "Payment reference", with: "COUNTER-42"
      end

      deposit_switch = find("label.panel-switch", text: "Return at checkout")
      click_in_overlay deposit_switch
      expect(find("select[name='security_deposit_release_method']", visible: :all)).to be_disabled
      click_in_overlay deposit_switch

      click_in_overlay "Complete checkout"
    end

    expect(page).to have_no_css("dialog#booking-checkout-sheet", wait: 3)
    expect(booking.reload.status).to eq("completed")
  end

  it "adds and removes a guest through booking action Sheets", js: true do
    visit hotel_booking_workspace_path(hotel, booking, tab: "guest_details")

    click_link "+ Add Guest"
    expect(page).to have_css("dialog#booking-guest-sheet[open]", wait: 3)
    within("#booking-guest-sheet") do
      fill_in "Full name", with: "Additional Guest"
      click_in_overlay "Add guest"
    end

    expect(page).to have_no_css("dialog#booking-guest-sheet", wait: 3)
    additional = booking.reload.booking_guests.find_by!(is_primary: false)
    visit hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: additional.id)

    click_link "Remove guest"
    expect(page).to have_css("dialog#booking-guest-removal-sheet[open]", wait: 3)
    within("#booking-guest-removal-sheet") { click_in_overlay "Remove guest" }

    expect(page).to have_no_css("dialog#booking-guest-removal-sheet", wait: 3)
    expect(booking.booking_guests.where(id: additional.id)).not_to exist
  end

  it "manages internal notes through booking action Sheets", js: true do
    visit hotel_booking_workspace_path(hotel, booking, tab: "booking_details")

    click_link "Add note"
    expect(page).to have_css("dialog#booking-internal-note-sheet[open]", wait: 3)
    within("#booking-internal-note-sheet") do
      fill_in "Internal note", with: "First operational note"
      click_in_overlay "Add note"
    end

    expect(page).to have_content("Note added.")
    expect(page).to have_content("First operational note")
    within("article", text: "First operational note") { click_link "Edit" }
    within("#booking-internal-note-sheet") do
      fill_in "Internal note", with: "Updated operational note"
      click_in_overlay "Save note"
    end

    expect(page).to have_content("Note updated.")
    expect(page).to have_content("Updated operational note")
    within("article", text: "Updated operational note") { click_link "History" }
    expect(page).to have_css("dialog#booking-internal-note-history-sheet[open]", wait: 3)
    expect(page).to have_content("First operational note")
    find("dialog#booking-internal-note-history-sheet").send_keys(:escape)
    expect(page).to have_no_css("dialog#booking-internal-note-history-sheet", wait: 3)

    within("article", text: "Updated operational note") { click_link "Delete" }
    expect(page).to have_css("dialog#booking-internal-note-deletion-sheet[open]", wait: 3)
    within("#booking-internal-note-deletion-sheet") { click_in_overlay "Delete note" }
    expect(page).to have_content("Note deleted.")
    expect(page).to have_no_content("Updated operational note")
  end

  xit "protects unsaved snapshot changes with the workspace alert", js: true do
    visit hotel_booking_workspace_path(hotel, booking, tab: "guest_details")

    fill_in "Full Name", with: "Unsaved Guest Name"

    click_link "Booking Details"
    expect(page).to have_css('[role="alertdialog"]', text: "Discard your changes?")
    click_button "Keep Editing"
    expect(page).to have_field("Full Name", with: "Unsaved Guest Name")
    expect(page).to have_current_path(hotel_booking_workspace_path(hotel, booking, tab: "guest_details"))

    click_link "Booking Details"
    within('[role="alertdialog"]') { click_button "Discard Changes" }

    expect(page).to have_current_path(hotel_booking_workspace_path(hotel, booking, tab: "booking_details"))
    expect(booking.reload.guest_name).not_to eq("Unsaved Guest Name")
  end

  it "prints the existing GRC in place without navigating or opening a window", js: true do
    visit hotel_booking_workspace_path(hotel, booking, tab: "guest_details")
    original_url = page.current_url

    page.execute_script <<~JS
      document.addEventListener("document-print:ready", (event) => {
        event.detail.frame.contentWindow.print = () => {
          window.__grcPrintCalled = true
          event.detail.frame.contentWindow.dispatchEvent(new Event("afterprint"))
        }
      }, { once: true })
    JS

    within("[data-testid='guest-details-footer']") { click_button "Print" }
    click_button "Guest Registration Card"

    expect(page).to have_no_css("iframe[data-document-print-frame]", wait: 3)
    expect(page.evaluate_script("window.__grcPrintCalled")).to be(true)
    expect(page.current_url).to eq(original_url)
    expect(page.driver.browser.window_handles.size).to eq(1)
  end

  xit "saves the selected guest from the full-width external footer", js: true do
    visit hotel_booking_workspace_path(hotel, booking, tab: "guest_details")
    profile_name = booking.primary_guest.name

    expect(page).to have_css("turbo-frame#booking_workspace > footer[data-testid='guest-details-footer']")
    fill_in "Full name", with: "Saved From Footer"
    click_button "Save Guest"

    primary_booking_guest = booking.booking_guests.find_by!(is_primary: true)
    expect(page).to have_current_path(hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: primary_booking_guest.id))
    expect(page).to have_field("Full name", with: "Saved From Footer")
    expect(booking.reload.guest_name).to eq("Saved From Footer")
    expect(booking.primary_guest.reload.name).to eq(profile_name)
  end

  it "updates the reusable guest only from the explicit split-save option", js: true do
    visit hotel_booking_workspace_path(hotel, booking, tab: "guest_details")

    expect(page).to have_field("Full name", wait: 10)
    fill_in "Full name", with: "Shared Guest Name"
    save_options_trigger = find("button[aria-label='More save options']")
    save_options_trigger.click
    expect(page.evaluate_script(<<~JS)).to be(true)
      (() => {
        const trigger = document.querySelector("button[aria-label='More save options']").getBoundingClientRect()
        const menu = document.querySelector("[data-testid='save-options-menu']").getBoundingClientRect()
        return menu.left < trigger.left && menu.right <= trigger.right + 1
      })()
    JS
    click_button "Save & Update Guest Record"

    expect(page).to have_content("Guest details and guest record updated.")
    expect(page).to have_field("Full name", with: "Shared Guest Name")
    expect(booking.reload.primary_guest.name).to eq("Shared Guest Name")
  end

  xit "clicks Apply changes in the billing routes offcanvas", js: true do
    role.permissions << Permission.find_or_create_by!(slug: "manage_folio_movements") { |record| record.name = "Manage Folio Movements" }
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    parent_code = create(:transaction_code, hotel: hotel, kind: "charge", code: "SPA", name: "Spa charge")

    visit hotel_booking_workspace_path(hotel, booking, tab: "billing_preferences")
    click_link "Change Billing Routes"

    expect(page).to have_css("#offcanvas_drawer_container.block", visible: :all)
    within("#offcanvas_drawer") do
      expect(page).to have_content(/change billing routes/i)
      expect(page).to have_content(parent_code.code)
      click_button "Apply changes"
    end
    expect(page).to have_css("#offcanvas_drawer_container.hidden", visible: :all, wait: 3)
  end
end
