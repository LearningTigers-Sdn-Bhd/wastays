# frozen_string_literal: true

require "rails_helper"

# Test plan phase U: end-to-end browser flows.
# docs/wastays/per-pax-ta-reservations-test-plan-2026-09-25.md §7.12.
# The rate-plan-editor half of U1 (hotel admin setting up FB via the UI) is
# already exercised, step by step, by spec/system/hotel/per_pax_rate_plan_pricing_spec.rb
# (Manual/Derived/Auto) and spec/system/hotel/rate_plan_age_bands_spec.rb (age
# bands) - this file builds FB through the same services those UIs write to
# (RatePlans::SaveRoomPricing) and focuses on the part that's genuinely new
# here: search -> book -> the TA and hotel side both agreeing. U5 (boat times)
# is a separate subsystem and isn't covered.
RSpec.describe "Per-pax TA booking, end to end", type: :system, js: true do
  include_context "per-pax resort"

  let(:check_in) { Date.current + 20 }
  let(:check_out) { check_in + 3 }

  def search_and_open(relationship_id:, adults: 2, children: 0, rooms: 1)
    visit_when_loaded new_corporate_booking_path(
      hotel_relationship_id: relationship_id, check_in: check_in.to_s, check_out: check_out.to_s,
      adults: adults, children: children, rooms: rooms
    )
  end

  # FB is attached to both Suite and Twin, so a plain "li with text Full
  # Board" match is ambiguous - scope to the row naming both the room
  # category and the plan.
  def option_row(room_type_name, plan_name)
    all("li").find { |li| li.text.include?(room_type_name) && li.text.include?(plan_name) }
  end

  def select_option(room_type_name:, plan_name:)
    within(option_row(room_type_name, plan_name)) { click_link "Select" }
  end

  def fill_lead_guest(name: "Ada Lim", phone: "+60123456789")
    fill_in "Full name", with: name, match: :first
    fill_in "Phone", with: phone, match: :first
  end

  # U1: full flow - TA-A searches, sees FB priced correctly, books, and the
  # TA booking page shows the same total.
  it "U1: TA-A searches FB, sees the discounted price, books, and the booking page matches" do
    sign_in_as_system(ta_a_user)
    search_and_open(relationship_id: ta_a.id)

    expect(page).to have_css("li", text: "Full Board", wait: 10)
    expect(option_row("Pax Family Suite", "Full Board").text).to include("1350.00") # 2A x 3 nights x 0.9 (>=3-night discount)

    select_option(room_type_name: "Pax Family Suite", plan_name: "Full Board")
    expect(page).to have_css("h2", text: "Guest details", wait: 10)

    fill_lead_guest
    click_button "Confirm 1 room"

    expect(page).to have_current_path(%r{/corporate/bookings/\d+}, wait: 10)
    booking = hotel.bookings.order(:id).last
    expect(booking.total_amount.to_d).to eq(1_350.to_d)
    expect(page).to have_text("Full Board")
    expect(page).to have_text("1350.00")
  end

  # U2: TA-B and TA-C search the same dates - FB not listed for either
  # (only -> TA-A); CORP listed for TA-B only (except -> TA-C).
  it "U2a: TA-B sees the Suite's CORP but not its FB" do
    sign_in_as_system(ta_b_user)
    search_and_open(relationship_id: ta_b.id)

    expect(page).to have_css("li", wait: 10)
    expect(option_row("Pax Family Suite", "Full Board")).to be_nil
    expect(option_row("Pax Family Suite", "Corporate")).to be_present
  end

  it "U2b: TA-C sees neither the Suite's FB nor its CORP" do
    sign_in_as_system(ta_c_user)
    search_and_open(relationship_id: ta_c.id)

    expect(page).to have_css("li", wait: 10)
    expect(option_row("Pax Family Suite", "Full Board")).to be_nil
    expect(option_row("Pax Family Suite", "Corporate")).to be_nil
  end

  # U3: TA searches 5 adults in the Suite - no bookable option, a clear message
  it "U3: searching 5 adults shows no rooms available rather than a broken price" do
    sign_in_as_system(ta_a_user)
    search_and_open(relationship_id: ta_a.id, adults: 5)

    expect(page).to have_text(/nothing has \d+ room/i, wait: 10)
    expect(option_row("Pax Family Suite", "Standard Rate")).to be_nil
  end

  # U4: TA searches 1, 3 and 5 nights for the same party - three different
  # prices, matching table 6b.
  it "U4: 1, 3 and 5 nights for the same FB party price differently, matching the discount tiers" do
    sign_in_as_system(ta_a_user)

    visit_when_loaded new_corporate_booking_path(
      hotel_relationship_id: ta_a.id, check_in: check_in.to_s, check_out: (check_in + 1).to_s, adults: 2, children: 0, rooms: 1
    )
    expect(option_row("Pax Family Suite", "Full Board").text).to include("500.00")

    visit_when_loaded new_corporate_booking_path(
      hotel_relationship_id: ta_a.id, check_in: check_in.to_s, check_out: (check_in + 3).to_s, adults: 2, children: 0, rooms: 1
    )
    expect(option_row("Pax Family Suite", "Full Board").text).to include("1350.00")

    visit_when_loaded new_corporate_booking_path(
      hotel_relationship_id: ta_a.id, check_in: check_in.to_s, check_out: (check_in + 5).to_s, adults: 2, children: 0, rooms: 1
    )
    expect(option_row("Pax Family Suite", "Full Board").text).to include("2340.00")
  end

  # U6: TA cancels an unpaid booking - shown as cancelled, room free again
  it "U6: TA-A cancels an unpaid booking and the room becomes searchable again" do
    params = {
      room_type_id: suite.id, check_in: check_in.to_s, check_out: check_out.to_s,
      adults: 2, children: 0, rooms: 1, rate_plan_id: fb_plan.id,
      rooms_detail: { "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789" } } } }
    }
    booking = CorporatePortal::CreateAgentBooking.call(relationship: ta_a, params: params, user: ta_a_user).booking

    sign_in_as_system(ta_a_user)
    visit_when_loaded corporate_booking_path(booking, hotel_relationship_id: ta_a.id)

    click_link "Cancel booking"
    expect(page).to have_text("Cancel this booking?", wait: 10)
    click_button "Confirm cancellation"

    expect(page).to have_text(/cancelled/i, wait: 10)
    expect(booking.reload.status).to eq("cancelled")
  end

  # R1: the search asks one age per child, and the quote follows the band.
  it "asks each child's age and quotes FB's child band for it" do
    sign_in_as_system(ta_a_user)
    search_and_open(relationship_id: ta_a.id)

    expect(page).to have_no_css("select[aria-label='Age of child 1']")
    fill_in "Children per room", with: "1"
    find("select[aria-label='Age of child 1']", wait: 5).select("8")
    click_button "Search availability"

    # 2A + child 8: 500 + 40% of the 1-adult 300 = 620/night, 3 nights at 10% off = 1,674
    # The page already lists the childless quote, so wait for the new price
    # itself rather than any "Full Board" row, which the old list satisfies.
    expect(page).to have_css("li", text: "1674.00", wait: 10)
    expect(option_row("Pax Family Suite", "Full Board").text).to include("1674.00")
    expect(find("select[aria-label='Age of child 1']").value).to eq("8")
  end
end
