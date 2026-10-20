# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Changing a booking's source", frozen_time: :business_day, type: :system do
  include_context "booking workspace system setup"

  it "corrects the source from the booking overview", js: true do
    booking.update!(source: "phone")

    visit hotel_booking_workspace_path(hotel, booking, tab: "booking_details")
    find("a[aria-label^='Change source of booking']").click

    expect(page).to have_css("dialog#booking-source-sheet[open]", wait: 3)
    within("#booking-source-sheet") do
      expect(page).to have_content("Currently recorded as Phone.")
      select "Agoda", from: "Booking source"
      click_button "Save source"
    end

    expect(page).to have_no_css("dialog#booking-source-sheet", wait: 3)
    expect(page).to have_content("Booking source updated.")
    within("table", text: /confirmation code/i) { expect(page).to have_content("Agoda") }
    expect(booking.reload.source).to eq("agoda")
  end
end
