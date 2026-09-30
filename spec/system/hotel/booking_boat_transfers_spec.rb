# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Booking boat transfers", frozen_time: :business_day, type: :system do
  include_context "booking workspace system setup"

  it "reveals custom time fields and restores saved Charter and Own selections", js: true do
    hotel.update!(allow_boat_information: true)
    lead = booking.booking_guests.find_by!(is_primary: true)
    lead.update!(boat_in_type: "charter", boat_in_at: Boats::Schedule.timestamp(hotel: hotel, date: booking.check_in, time: "18:03"), boat_out_type: "own")
    visit hotel_booking_workspace_path(hotel, booking, tab: "guest_details")

    inbound = find("[data-controller='boat-transfer']:has(select[name='booking_guest[boat_in_time]'])")
    expect(inbound).to have_css("[data-boat-transfer-target='custom']", visible: true)
    expect(inbound).to have_css(".panel-time-picker__value", text: "18:03")
    within(inbound) do
      find("button[aria-haspopup='listbox']").click
      find("[role='option']", text: "No boat transfer", exact_text: true).click
    end
    expect(inbound).to have_css("[data-boat-transfer-target='custom']", visible: false)
    within(inbound) do
      find("button[aria-haspopup='listbox']").click
      find("[role='option']", text: "Charter Boat", exact_text: true).click
    end
    expect(inbound).to have_css("[data-boat-transfer-target='custom']", visible: true)
    expect(inbound).to have_css(".panel-time-picker__value", text: "18:03")

    outbound = find("[data-controller='boat-transfer']:has(select[name='booking_guest[boat_out_time]'])")
    expect(outbound).to have_css("[data-boat-transfer-target='custom']", visible: true)
    expect(outbound).to have_css(".panel-select-menu__value", text: "Own Boat")
    within(inbound) { find(".panel-time-picker__display").click }
    find("[data-time-option='minutes'][data-time-value='7']", visible: true).click
    find("h1").click
    expect(inbound).to have_css(".panel-time-picker__value", text: "18:07")
    find("[data-testid='guest-save-trigger']").click
    within("#guest-save-scope-dialog") { click_button "Save" }
    expect(page).to have_text("Guest details saved.")
    expect(lead.reload).to have_attributes(boat_in_type: "charter", boat_out_type: "own", boat_out_at: nil)
    expect(Boats::Schedule.time_of_day(hotel: hotel, timestamp: lead.boat_in_at)).to eq("18:07")
  end
end
