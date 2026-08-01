# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Booking workspace actions", frozen_time: :business_day, type: :system do
  include_context "booking workspace system setup"

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
      expect(page).to have_select("Booking", disabled: true, visible: :all)
      click_in_overlay find("summary", text: "View Changes")
      expect(page).to have_content("Pending")
      expect(page).to have_content("Confirmed")
      click_link "Notes"
    end

    expect(page).to have_css("dialog#booking-audit-trail-sheet[open]", wait: 3)
    within("#booking-audit-trail-sheet") do
      expect(page).to have_content("No events match these filters.")
      click_link "All"
    end

    expect(page).to have_css("dialog#booking-audit-trail-sheet[open]", wait: 3)
    within("#booking-audit-trail-sheet") do
      expect(page).to have_content("Booking details updated")
    end
    page.send_keys(:escape)

    expect(page).to have_no_css("dialog#booking-audit-trail-sheet", wait: 3)
    expect(page).to have_content(booking.confirmation_token)
  end

  it "opens room and rate Sheets for the selected group child", js: true do
    group = create(:group_booking, hotel: hotel)
    booking.update!(group_booking: group, group_position: 1)
    sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, guest_name: "Selected Rate Guest")
    room_type = create(:room_type, hotel: hotel, name: "Lagoon Villa")
    rate_plan = create(:rate_plan, hotel: hotel, name: "Lagoon Flexible", room_type: room_type)
    create(:booking_room, booking: sibling, room_type: room_type, rate_plan: rate_plan, room_number: "202", subtotal: 780)

    visit hotel_booking_workspace_path(hotel, sibling, tab: "room_and_rate", child_booking_id: sibling.id)
    click_link "Change room"

    expect(page).to have_css("dialog#booking-room-sheet[open]", wait: 3)
    within("#booking-room-sheet") do
      expect(page).to have_content("Lagoon Villa · 202")
    end
    find("dialog#booking-room-sheet").send_keys(:escape)
    expect(page).to have_no_css("dialog#booking-room-sheet", wait: 3)

    click_link "Change rate"
    expect(page).to have_css("dialog#change-rate-alert[open]", wait: 3)
    within("#change-rate-alert") { click_link "Continue to editor" }

    expect(page).to have_css("dialog#booking-rate-sheet[open]", wait: 3)
    within("#booking-rate-sheet") do
      expect(page).to have_content("Selected Rate Guest")
      expect(page).to have_content("Lagoon Flexible")
    end
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

    primary_folio = booking.booking_folios.find_by!(is_primary: true)
    create(:deposit, booking: booking, hotel: hotel, amount: 175, status: "held")

    relationship = create(:hotel_corporate_account, :direct_bill, hotel: hotel)
    company_folio = create(
      :booking_folio,
      :secondary,
      booking: booking,
      hotel: hotel,
      label: "Company Folio",
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

    click_link "Add guest"
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

  it "opens selective billing routes, nests Add folio, and applies from Sheets", js: true do
    %w[manage_folio_movements manage_folio_windows].each do |slug|
      role.permissions << Permission.find_or_create_by!(slug: slug) { |record| record.name = slug.humanize }
    end
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    parent_code = create(:transaction_code, hotel: hotel, kind: "charge", code: "SPA", name: "Spa charge")
    primary_party = booking.booking_guests.find_by!(is_primary: true).booking_billing_party
    booking.booking_folio.update!(booking_billing_party: primary_party)
    company_party = create(:booking_billing_party, :company, booking: booking, hotel: hotel)
    company_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, label: "Company Folio",
      booking_billing_party: company_party, payer_type: "company", hotel_corporate_account: company_party.hotel_corporate_account)

    visit hotel_booking_workspace_path(hotel, booking, tab: "billing_preferences")
    click_link "Change Billing Routes"

    expect(page).to have_css("turbo-frame#folio_action_sheet dialog#folio-billing-routes-sheet[open]")
    within("dialog#folio-billing-routes-sheet") do
      expect(page).to have_content(/change billing routes/i)
      expect(page).to have_content(parent_code.code)

      click_in_overlay "Add folio"
    end

    expect(page).to have_css("turbo-frame#folio_action_sheet_secondary dialog#folio-window-sheet[open]")
    find("dialog#folio-window-sheet").send_keys(:escape)
    expect(page).to have_no_css("turbo-frame#folio_action_sheet_secondary dialog#folio-window-sheet")
    expect(page).to have_css("dialog#folio-billing-routes-sheet[open]")

    within("dialog#folio-billing-routes-sheet") do
      row = find("tr[data-route-level='parent'][data-code-id='#{parent_code.id}']")
      party_select = row.find("select[name='routes[#{parent_code.id}][billing_party_id]']", visible: :all)
      page.execute_script("arguments[0].value = arguments[1]; arguments[0].dispatchEvent(new Event('change', { bubbles: true }))", party_select, company_party.id.to_s)
      folio_select = row.find("select[name='routes[#{parent_code.id}][target_folio_id]']", visible: :all)
      expect(folio_select).to have_css("option[value='#{company_folio.id}']", visible: :all)
      page.execute_script("arguments[0].value = arguments[1]; arguments[0].dispatchEvent(new Event('change', { bubbles: true }))", folio_select, company_folio.id.to_s)
      click_in_overlay "Apply changes"
    end

    expect(page).to have_current_path(hotel_booking_workspace_path(hotel, booking, tab: "billing_preferences"))
    expect(page).to have_no_css("dialog#folio-billing-routes-sheet", wait: 5)
    expect(booking.folio_routing_rules.active.find_by(transaction_code: parent_code)&.target_folio).to eq(company_folio)
  end
end
