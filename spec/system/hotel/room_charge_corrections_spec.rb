# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Completed booking room-charge correction", frozen_time: :business_day, type: :system do
  include_context "completed room-charge correction"

  before do
    driven_by(:cuprite)
    sign_in_as_system(actor)
  end

  it "enters, reviews, goes back, and confirms a correction in the sheet", js: true do
    visit hotel_booking_workspace_path(hotel, booking, tab: "room_and_rate")
    click_link "Correct room charges"
    expect(page).to have_css("dialog#booking-room-charge-correction-sheet[open]")
    within("#booking-room-charge-correction-sheet") do
      fill_in "Set all nights", with: "86.40"
      fill_in "Correction reason", with: correction_input[:correction_reason]
      click_button "Review correction"
      expect(page).to have_content("Review room-charge correction")
      expect(page).to have_content("-21.60")
      expect(page).to have_content("Tourism Tax is unchanged.")
      page.save_screenshot("/private/tmp/wastays-room-charge-correction-review.png")
      click_button "Back"
      expect(page).to have_css("input[name='room_charge_correction[nightly_amounts][#{correction_date.iso8601}]'][value='86.40']")
      expect(page).to have_field("Correction reason", with: correction_input[:correction_reason])
      click_button "Review correction"
      click_button "Confirm correction"
    end
    expect(page).to have_no_css("dialog#booking-room-charge-correction-sheet")
    expect(booking.reload.total_amount).to eq("86.4".to_d)
    expect(booking.status).to eq("completed")
    expect(page).to have_content("MYR 80.00")
  end

  it "shows server errors and restores sheet focus on a narrow screen", js: true do
    page.current_window.resize_to(390, 844)
    visit hotel_booking_workspace_path(hotel, booking, tab: "room_and_rate")
    click_link "Correct room charges"
    within("#booking-room-charge-correction-sheet") do
      fill_in "Set all nights", with: "108"
      fill_in "Correction reason", with: correction_input[:correction_reason]
      click_button "Review correction"
      expect(page).to have_content("The corrected room charges are unchanged.")
      expect(page).to have_field("Correction reason", with: correction_input[:correction_reason])
    end
    page.save_screenshot("/private/tmp/wastays-room-charge-correction-mobile.png")
    expect(page.evaluate_script("document.querySelector('#booking-room-charge-correction-sheet').contains(document.activeElement)")).to be(true)
    find("dialog#booking-room-charge-correction-sheet").send_keys(:escape)
    expect(page).to have_no_css("dialog#booking-room-charge-correction-sheet")
  ensure
    page.current_window.resize_to(1400, 1400)
  end
end
