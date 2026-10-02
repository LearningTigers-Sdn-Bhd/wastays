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

  # The booking wizard: the stay's dates, then rooms (a category, who is in it, a
  # rate), then guests. These drive its URLs directly where a step is not what is
  # under test, and click through it where it is.
  def rooms_url(relationship_id:, nights: 3, **extra)
    new_corporate_booking_path(
      hotel_relationship_id: relationship_id, check_in: check_in.to_s, check_out: (check_in + nights).to_s,
      step: "rooms", **extra
    )
  end

  # The rates one category is sold at, for a party.
  def open_rates(relationship_id:, room_type: suite, adults: 2, children: 0, child_ages: nil, quantity: 1, nights: 3)
    visit_when_loaded rooms_url(
      relationship_id: relationship_id, nights: nights, stage: "rate", add_room_type_id: room_type.id,
      add_adults: adults, add_children: children, add_child_ages: child_ages, add_quantity: quantity
    )
  end

  def rate_row(plan_name)
    all("[data-testid='agent-rate']").find { |row| row.text.include?(plan_name) }
  end

  # Adds the rate to the stay and goes on to the guests.
  def add_rate_and_continue(plan_name)
    within(rate_row(plan_name)) { click_link "Add to stay" }
    click_link "Continue to guests"
  end

  def fill_lead_guest(name: "Ada Lim", phone: "+60123456789")
    fill_in "Full name", with: name, match: :first
    fill_in "Phone", with: phone, match: :first
  end

  # U1: full flow - TA-A searches, sees FB priced correctly, books, and the
  # TA booking page shows the same total.
  it "U1: TA-A searches FB, sees the discounted price, books, and the booking page matches" do
    sign_in_as_system(ta_a_user)
    open_rates(relationship_id: ta_a.id)

    expect(page).to have_css("[data-testid='agent-rate']", text: "Full Board", wait: 10)
    expect(rate_row("Full Board").text).to include("1,350.00") # 2A x 3 nights x 0.9 (>=3-night discount)

    add_rate_and_continue("Full Board")
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
    open_rates(relationship_id: ta_b.id)

    expect(page).to have_css("[data-testid='agent-rate']", wait: 10)
    expect(rate_row("Full Board")).to be_nil
    expect(rate_row("Corporate")).to be_present
  end

  it "U2b: TA-C sees neither the Suite's FB nor its CORP" do
    sign_in_as_system(ta_c_user)
    open_rates(relationship_id: ta_c.id)

    expect(page).to have_css("[data-testid='agent-rate']", wait: 10)
    expect(rate_row("Full Board")).to be_nil
    expect(rate_row("Corporate")).to be_nil
  end

  # U3: TA searches 5 adults in the Suite - no bookable option, a clear message
  it "U3: asking for 5 adults in the Suite is refused with a message, not a broken price" do
    sign_in_as_system(ta_a_user)
    open_rates(relationship_id: ta_a.id, adults: 5)

    expect(page).to have_text(suite.occupancy_limit_message, wait: 10)
    expect(rate_row("Standard Rate")).to be_nil
  end

  # U4: TA searches 1, 3 and 5 nights for the same party - three different
  # prices, matching table 6b.
  it "U4: 1, 3 and 5 nights for the same FB party price differently, matching the discount tiers" do
    sign_in_as_system(ta_a_user)

    open_rates(relationship_id: ta_a.id, nights: 1)
    expect(rate_row("Full Board").text).to include("500.00")

    open_rates(relationship_id: ta_a.id, nights: 3)
    expect(rate_row("Full Board").text).to include("1,350.00")

    open_rates(relationship_id: ta_a.id, nights: 5)
    expect(rate_row("Full Board").text).to include("2,340.00")
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

  # M1: one stay of different rooms -- a different category, rate and party for each --
  # built line by line, then booked together under one group.
  it "M1: TA-A books a Suite for 2 on Full Board and a Twin for 1 on Standard, in one stay" do
    sign_in_as_system(ta_a_user)
    visit_when_loaded rooms_url(relationship_id: ta_a.id)

    within(find("[data-testid='agent-room-type']", text: "Pax Family Suite", wait: 10)) { click_link "Choose" }
    fill_in "Adults per room", with: "2"
    click_button "See rates"
    within(find("[data-testid='agent-rate']", text: "Full Board", wait: 10)) { click_link "Add to stay" }

    expect(page).to have_css("[data-testid='cart-line']", count: 1, wait: 10)
    click_link "Add another room"
    within(find("[data-testid='agent-room-type']", text: "Pax Deluxe Twin", wait: 10)) { click_link "Choose" }
    fill_in "Adults per room", with: "1"
    click_button "See rates"
    within(find("[data-testid='agent-rate']", text: "Standard Rate", wait: 10)) { click_link "Add to stay" }

    expect(page).to have_css("[data-testid='cart-line']", count: 2, wait: 10)
    expect(page.find("[data-testid='cart-total']").text).to include("2 rooms")
    click_link "Continue to guests"

    expect(page).to have_css("[data-testid='guest-room']", count: 2, wait: 10)
    names = all("input[name$='[name]']")
    names[0].set("Ada Lim")
    all("input[type='tel']")[0].set("+60123456789")
    # The first room has two adults to name, so the second room's lead is the third.
    names[2].set("Bo Tan")
    all("input[type='tel']")[2].set("+60127654321")
    click_button "Confirm 2 rooms"

    expect(page).to have_current_path(%r{/corporate/bookings/\d+}, wait: 10)
    bookings = hotel.bookings.order(:id).last(2)
    expect(bookings.map { |booking| booking.booking_rooms.first.room_type }).to eq([ suite, twin ])
    expect(bookings.map { |booking| booking.booking_rooms.first.rate_plan }).to eq([ fb_plan, std_plan ])
    expect(bookings.map(&:adults)).to eq([ 2, 1 ])
    expect(bookings.map(&:group_booking_id).uniq.size).to eq(1)
    expect(page).to have_text("Part of a 2-room stay")
  end

  # R1: the party step asks one age per child, and the quote follows the band.
  it "asks each child's age and quotes FB's child band for it" do
    sign_in_as_system(ta_a_user)
    visit_when_loaded rooms_url(relationship_id: ta_a.id, stage: "occupancy", add_room_type_id: suite.id)

    expect(page).to have_no_css("select[aria-label='Age of child 1']")
    fill_in "Children per room", with: "1"
    find("select[aria-label='Age of child 1']", wait: 5).select("8")
    click_button "See rates"

    # 2A + child 8: 500 + 40% of the 1-adult 300 = 620/night, 3 nights at 10% off = 1,674
    expect(page).to have_css("[data-testid='agent-rate']", text: "1,674.00", wait: 10)
    expect(rate_row("Full Board").text).to include("1,674.00")
  end
end
