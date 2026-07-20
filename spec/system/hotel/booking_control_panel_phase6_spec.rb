# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Booking control panel Phase 6", type: :system do
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
    visit hotel_booking_control_panel_path(hotel, booking, tab: "room_and_rate")
    expect(page).to have_css('[data-layout-mode="left_and_center"]')
    expect(page).to have_content("Room & Rate")

    click_link "Guest Details"
    expect(page).to have_current_path(hotel_booking_control_panel_path(hotel, booking, tab: "guest_details"))
    expect(page).to have_css('[data-layout-mode="left_and_center"]')
    expect(page).to have_content("Primary guest for this room")
    expect(page).to have_field("Email", with: "hanami@mail.com")
    expect(page).to have_content("Guest details recorded for this stay.")
    expect(page).to have_button("Save Guest")

    click_link "Security Deposits"
    expect(page).to have_css('[data-layout-mode="left_and_center"]')
    expect(page).to have_content("Security Deposits")
    expect(page).to have_content("MYR 175.00")

    click_link "Billing Preferences"
    expect(page).to have_css('[data-layout-mode="left_and_center"]')
    expect(page).to have_content("Billing parties")

    click_link "Folio Operations"
    expect(page).to have_css('[data-layout-mode="left_and_center"]')
    expect(page).to have_content("Ledger")
    expect(page).not_to have_content("Manage Folio Windows")

    click_link "Requests"
    expect(page).to have_css('[data-layout-mode="left_and_center"]')
    expect(page).to have_content("Fresh towels")
    expect(page).to have_content("Noisy hallway")
  end

  xit "re-renders the active tab with Turbo frame navigation", js: true do
    visit hotel_booking_control_panel_path(hotel, booking, tab: "room_and_rate")

    within("#booking-control-tabs") do
      expect(page).to have_css("a[aria-current='page']", text: "Room & Rate")
      click_link "Guest Details"
    end

    within("#booking-control-tabs") do
      expect(page).to have_css("a[aria-current='page']", text: "Guest Details")
      expect(page).to have_no_css("a[aria-current='page']", text: "Room & Rate")
    end

    expect(page).to have_current_path(hotel_booking_control_panel_path(hotel, booking, tab: "guest_details"))
    expect(page).to have_content("Primary guest for this room")
    expect(page).to have_css("#hotel-breadcrumb", text: "Booking Control Panel")
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

  xit "protects unsaved snapshot changes with the control-panel alert", js: true do
    visit hotel_booking_control_panel_path(hotel, booking, tab: "guest_details")

    fill_in "Full Name", with: "Unsaved Guest Name"

    click_link "Booking Details"
    expect(page).to have_css('[role="alertdialog"]', text: "Discard your changes?")
    click_button "Keep Editing"
    expect(page).to have_field("Full Name", with: "Unsaved Guest Name")
    expect(page).to have_current_path(hotel_booking_control_panel_path(hotel, booking, tab: "guest_details"))

    click_link "Booking Details"
    within('[role="alertdialog"]') { click_button "Discard Changes" }

    expect(page).to have_current_path(hotel_booking_control_panel_path(hotel, booking, tab: "booking_details"))
    expect(booking.reload.guest_name).not_to eq("Unsaved Guest Name")
  end

  it "prints the existing GRC in place without navigating or opening a window", js: true do
    visit hotel_booking_control_panel_path(hotel, booking, tab: "guest_details")
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
    visit hotel_booking_control_panel_path(hotel, booking, tab: "guest_details")
    profile_name = booking.primary_guest.name

    expect(page).to have_css("turbo-frame#booking_control_panel_workspace > footer[data-testid='guest-details-footer']")
    fill_in "Full Name", with: "Saved From Footer"
    click_button "Save Guest"

    primary_booking_guest = booking.booking_guests.find_by!(is_primary: true)
    expect(page).to have_current_path(hotel_booking_control_panel_path(hotel, booking, tab: "guest_details", booking_guest_id: primary_booking_guest.id))
    expect(page).to have_field("Full Name", with: "Saved From Footer")
    expect(booking.reload.guest_name).to eq("Saved From Footer")
    expect(booking.primary_guest.reload.name).to eq(profile_name)
  end

  it "updates the reusable guest only from the explicit split-save option", js: true do
    visit hotel_booking_control_panel_path(hotel, booking, tab: "guest_details")

    expect(page).to have_field("Full Name", wait: 10)
    fill_in "Full Name", with: "Shared Guest Name"
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
    expect(page).to have_field("Full Name", with: "Shared Guest Name")
    expect(booking.reload.primary_guest.name).to eq("Shared Guest Name")
  end

  xit "clicks Apply changes in the billing routes offcanvas", js: true do
    role.permissions << Permission.find_or_create_by!(slug: "manage_folio_movements") { |record| record.name = "Manage Folio Movements" }
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    parent_code = create(:transaction_code, hotel: hotel, kind: "charge", code: "SPA", name: "Spa charge")

    visit hotel_booking_control_panel_path(hotel, booking, tab: "billing_preferences")
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
