# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Booking workspace mobile entity selection", :business_day, type: :system do
  include_context "booking workspace system setup"

  it "selects a folio from the mobile Sheet and focuses its heading", :mobile, js: true do
    primary = booking.booking_folios.find_by!(is_primary: true)
    secondary = create(:booking_folio, :secondary, booking: booking, hotel: hotel, name: "Mobile Company Folio")
    page.current_window.resize_to(390, 844)
    visit hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: primary.id)

    click_button "Choose Folio"
    expect(page).to have_css("dialog#booking-entity-selector-sheet[open]", wait: 3)
    page.current_window.resize_to(1400, 1400)
    expect(page).to have_css("dialog#booking-entity-selector-sheet[open]", visible: true)
    page.current_window.resize_to(390, 844)
    find("#booking-entity-selector-sheet a[href*='folio_id=#{secondary.id}']").click

    expect(page).to have_current_path(hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: secondary.id))
    expect(page).to have_no_css("dialog#booking-entity-selector-sheet[open]")
    expect(page).to have_css("#folio-operations-panel:focus")

    click_button "Choose Folio"
    perform_turbo_navigation do
      find("#booking-entity-selector-sheet a[href*='folio_id=#{primary.id}']").click
    end
    expect(page).to have_current_path(hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: primary.id))

    click_button "Choose Folio"
    find("#booking-entity-selector-sheet a[href*='folio_id=#{secondary.id}']").click
    expect(page).to have_current_path(hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: secondary.id))
    expect(page).to have_css("#folio-operations-panel:focus")
  end

  it "protects dirty guest details while selecting from the mobile Sheet", :mobile, js: true do
    primary = booking.booking_guests.find_by!(is_primary: true)
    additional = create(:booking_guest, booking: booking, guest: create(:guest, name: "Mobile Guest Target"), is_primary: false)
    page.current_window.resize_to(390, 844)
    visit hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: primary.id)
    fill_in "Full name", with: "Unsaved Mobile Name"

    click_button "Choose Guest"
    within("#booking-entity-selector-sheet") { click_link "Mobile Guest Target" }
    expect(page).to have_css('[role="alertdialog"]', text: "Discard your changes?")
    click_button "Keep Editing"

    expect(page).to have_css("dialog#booking-entity-selector-sheet[open]")
    expect(page).to have_field("Full name", with: "Unsaved Mobile Name")
    expect(page.evaluate_script("document.activeElement?.textContent")).to include("Mobile Guest Target")

    within("#booking-entity-selector-sheet") { click_link "Mobile Guest Target" }
    within('[role="alertdialog"]') { click_button "Discard Changes" }

    expect(page).to have_current_path(hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: additional.id))
    expect(page).to have_css("#guest-details-panel:focus")
  end

  it "scrolls a long grouped guest Sheet and selects the final guest", :mobile, js: true do
    group = create(:group_booking, hotel: hotel)
    booking.update!(group_booking: group, group_position: 1)
    booking.booking_rooms.first.update!(room_number: "101")
    target_booking = nil
    target_guest = nil

    12.times do |index|
      child = create(:booking, hotel: hotel, group_booking: group, group_position: index + 2)
      create(:booking_room, booking: child, room_number: (index + 102).to_s)
      child_guest = create(:booking_guest, booking: child, guest: create(:guest, name: "Grouped Mobile Guest #{index + 1}"), is_primary: true)
      if index == 11
        target_booking = child
        target_guest = child_guest
      end
    end

    page.current_window.resize_to(390, 844)
    visit hotel_booking_workspace_path(hotel, booking, tab: "guest_details")
    click_button "Choose Guest"

    expect(page.evaluate_script(<<~JS)).to be(true)
      (() => {
        const body = document.querySelector('#booking-entity-selector-sheet [data-panels-ui--sheet-target="panel"] > .custom-scrollbar')
        return body.scrollHeight > body.clientHeight
      })()
    JS
    within("#booking-entity-selector-sheet") { click_link "Grouped Mobile Guest 12" }

    expect(page).to have_current_path(hotel_booking_workspace_path(hotel, target_booking, tab: "guest_details", booking_guest_id: target_guest.id))
    expect(page).to have_css("#guest-details-panel:focus")
  end
end
