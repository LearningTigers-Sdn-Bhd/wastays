# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Booking workspace guest editing", frozen_time: :business_day, type: :system do
  include_context "booking workspace system setup"

  it "protects unsaved snapshot changes with the workspace alert", js: true do
    visit hotel_booking_workspace_path(hotel, booking, tab: "guest_details")

    fill_in "Full name", with: "Unsaved Guest Name"

    click_link "Overview"
    expect(page).to have_css('[role="alertdialog"]', text: "Discard your changes?")
    click_button "Keep Editing"
    expect(page).to have_field("Full name", with: "Unsaved Guest Name")
    expect(page).to have_current_path(hotel_booking_workspace_path(hotel, booking, tab: "guest_details"))

    click_link "Overview"
    within('[role="alertdialog"]') { click_button "Discard Changes" }

    expect(page).to have_current_path(hotel_booking_workspace_path(hotel, booking, tab: "booking_details"))
    expect(booking.reload.guest_name).not_to eq("Unsaved Guest Name")
  end

  it "protects unsaved changes while switching guests", js: true do
    primary = booking.booking_guests.find_by!(is_primary: true)
    additional = create(:booking_guest, booking: booking, guest: create(:guest, name: "Switch Target Guest"), is_primary: false)
    visit hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: primary.id)
    fill_in "Full name", with: "Unsaved Primary Name"

    within('nav[aria-label="Booking guests"]') { click_link "Switch Target Guest" }
    expect(page).to have_css('[role="alertdialog"]', text: "Discard your changes?")
    click_button "Keep Editing"
    expect(page).to have_field("Full name", with: "Unsaved Primary Name")

    within('nav[aria-label="Booking guests"]') { click_link "Switch Target Guest" }
    within('[role="alertdialog"]') { click_button "Discard Changes" }

    expect(page).to have_current_path(hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: additional.id))
    expect(page).to have_css("[data-testid='workspace-entity-rail'] a[aria-current='page']", text: "Switch Target Guest")
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

  it "saves the selected guest from the footer inside the content column", js: true do
    visit hotel_booking_workspace_path(hotel, booking, tab: "guest_details")
    profile_name = booking.primary_guest.name

    expect(page).to have_css("#guest-details-panel > footer[data-testid='guest-details-footer']")
    expect(page).to have_no_css("turbo-frame#booking_workspace > footer[data-testid='guest-details-footer']")
    fill_in "Full name", with: "Saved From Footer"
    click_button "Save for this booking only"

    primary_booking_guest = booking.booking_guests.find_by!(is_primary: true)
    expect(page).to have_current_path(hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: primary_booking_guest.id))
    expect(page).to have_field("Full name", with: "Saved From Footer")
    expect(booking.reload.guest_name).to eq("Saved From Footer")
    expect(booking.primary_guest.reload.name).to eq(profile_name)
  end

  it "preserves submitted guest values, errors, and invalid-field focus", js: true do
    visit hotel_booking_workspace_path(hotel, booking, tab: "guest_details")
    fill_in "Email", with: "submitted@example.com"
    page.execute_script("document.querySelector('input[name=\"guest[name]\"]').removeAttribute('required')")
    fill_in "Full name", with: ""

    click_button "Save for this booking only"

    expect(page).to have_css("[data-guest-details-error-summary]", text: "Name can't be blank")
    expect(page).to have_field("Email", with: "submitted@example.com")
    expect(page).to have_field("Full name", with: "")
    expect(page.evaluate_script("document.activeElement === document.querySelector('input[name=\"guest[name]\"]')")).to be(true)
  end

  it "switches standalone guests with back and forward history", js: true do
    primary = booking.booking_guests.find_by!(is_primary: true)
    additional = create(:booking_guest, booking: booking, guest: create(:guest, name: "History Guest"), is_primary: false)
    primary_path = hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: primary.id)
    additional_path = hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: additional.id)
    visit primary_path

    within('nav[aria-label="Booking guests"]') { click_link "History Guest" }
    expect(page).to have_current_path(additional_path)
    expect(page).to have_css("nav[aria-label='Booking guests'] a[aria-current='page']", text: "History Guest")

    page.go_back
    expect(page).to have_current_path(primary_path)
    expect(page).to have_css("nav[aria-label='Booking guests'] a[aria-current='page']", text: primary.guest.name)

    page.go_forward
    expect(page).to have_current_path(additional_path)
    expect(page).to have_css("[data-testid='workspace-entity-rail'] a[aria-current='page']", text: "History Guest")
  end

  it "switches guests across group child bookings", js: true do
    group = create(:group_booking, hotel: hotel)
    booking.update!(group_booking: group, group_position: 1)
    booking.booking_rooms.first.update!(room_number: "101")
    sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
    create(:booking_room, booking: sibling, room_number: "102")
    sibling_guest = create(:booking_guest, booking: sibling, guest: create(:guest, name: "Room 102 Guest"), is_primary: true)
    visit hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: booking.booking_guests.find_by!(is_primary: true).id)

    within('nav[aria-label="Booking guests"]') { click_link "Room 102 Guest" }

    expect(page).to have_current_path(hotel_booking_workspace_path(hotel, sibling, tab: "guest_details", booking_guest_id: sibling_guest.id))
    expect(page).to have_css(
      "nav[aria-label='Booking guests'] section[aria-labelledby='desktop-guest-group-#{sibling.id}'] a[aria-current='page']",
      text: "Room 102 Guest"
    )
    expect(page).not_to have_content(sibling.formatted_reservation_number)
  end

  it "updates the reusable guest only from the explicit full-save option", js: true do
    visit hotel_booking_workspace_path(hotel, booking, tab: "guest_details")

    expect(page).to have_field("Full name", wait: 10)
    fill_in "Full name", with: "Shared Guest Name"
    click_button "Save guest (full)"

    expect(page).to have_content("Guest details and guest record updated.")
    expect(page).to have_field("Full name", with: "Shared Guest Name")
    expect(booking.reload.primary_guest.name).to eq("Shared Guest Name")
  end
end
