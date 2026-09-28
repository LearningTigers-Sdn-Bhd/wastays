# frozen_string_literal: true

require "rails_helper"

# Test plan §8 edge cases.
# docs/wastays/per-pax-ta-reservations-test-plan-2026-09-25.md §8.
RSpec.describe "Per-pax edge cases" do
  include_context "per-pax resort"

  let(:check_in) { Date.current + 20 }

  def book(plan:, room_type: suite, adults:, children: 0, nights: 1, relationship: ta_a, actor: ta_a_user, rooms: 1, extra_rooms_detail: {})
    detail = { "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789" } } } }.merge(extra_rooms_detail)
    params = {
      room_type_id: room_type.id, check_in: check_in.to_s, check_out: (check_in + nights).to_s,
      adults: adults, children: children, rooms: rooms, rate_plan_id: plan.id, rooms_detail: detail
    }
    CorporatePortal::CreateAgentBooking.call(relationship: relationship, params: params, user: actor)
  end

  # children as "" / nil
  it "children blank/nil is treated as 0 guests, not an error" do
    result = book(plan: std_plan, adults: 2, children: "")

    expect(result).to be_success
    expect(result.booking.children).to eq(0)
    expect(result.booking.total_amount.to_d).to eq(440.to_d) # STD 2A price
  end

  # adults: 0 (RECORDED) - CreateManualBooking floors adults to 1
  # ([adults.to_i, 1].max in booking_params), but the availability pre-check
  # (CreateAgentBooking#check_availability -> AgentStaySearch) uses the raw,
  # un-floored adults param - 0 has no occupancy price, so the option is
  # unpriced/unavailable and the whole booking is refused before the floor
  # ever applies. Requesting 0 adults is refused, not silently booked as 1.
  it "adults: 0 is refused at the availability check, not silently floored to 1 (RECORDED)" do
    result = book(plan: std_plan, adults: 0, children: 0)

    expect(result).not_to be_success # RECORDED
  end

  # a party at exactly the room max (4A+2C Suite) vs one over it
  it "a party at exactly the room max (4A + 2C) books; one more adult does not" do
    at_max = CorporatePortal::AgentStaySearch.call(
      hotel: hotel, check_in: check_in, check_out: check_in + 1, adults: 4, children: 2, relationship: ta_a
    ).options.find { |o| o.room_type == suite && o.rate_plan == std_plan }
    expect(at_max).to be_present
    expect(at_max.per_room_amount).to be_present

    # AgentStaySearch drops an unpriceable option entirely (filter_map), so
    # 5 adults on the 4-max Suite isn't offered at all, not offered-with-no-price.
    over_max = CorporatePortal::AgentStaySearch.call(
      hotel: hotel, check_in: check_in, check_out: check_in + 1, adults: 5, children: 0, relationship: ta_a
    ).options.find { |o| o.room_type == suite && o.rate_plan == std_plan }
    expect(over_max).to be_blank
  end

  # the Twin room (max 2A/1C) with 2A+1C and 2A+2C (over max_children)
  it "the Twin room (max 2A/1C) is offered for 2A+1C but not 2A+2C, and says why" do
    within_capacity = CorporatePortal::AgentStaySearch.call(
      hotel: hotel, check_in: check_in, check_out: check_in + 1, adults: 2, children: 1, relationship: ta_a
    )
    expect(within_capacity.options.map(&:room_type)).to include(twin)

    over_capacity = CorporatePortal::AgentStaySearch.call(
      hotel: hotel, check_in: check_in, check_out: check_in + 1, adults: 2, children: 2, relationship: ta_a
    )
    expect(over_capacity.options.map(&:room_type)).not_to include(twin)
    expect(over_capacity.too_small).to eq([ twin ])
    expect(twin.occupancy_limit_message).to eq("Pax Deluxe Twin holds up to 2 adults and 1 child.")
  end

  it "refuses a TA booking over the room's child limit" do
    result = CorporatePortal::CreateAgentBooking.call(
      relationship: ta_a, user: ta_a_user,
      params: {
        room_type_id: twin.id, rate_plan_id: std_plan.id, check_in: check_in.to_s, check_out: (check_in + 1).to_s,
        adults: 2, children: 2, rooms: 1,
        rooms_detail: { "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789" } } } }
      }
    )

    expect(result).not_to be_success
    expect(result.errors).to eq([ "Pax Deluxe Twin holds up to 2 adults and 1 child." ])
  end

  # Auto ladder clamping at 0
  it "an Auto ladder decrease that would go negative clamps at 0, not negative" do
    plan = create(:rate_plan, :custom, hotel: hotel, name: "Auto Clamp Test", ta_access: "hidden")
    save_auto_prices!(plan, suite, anchor: 100, primary_occupancy: 2, decrease_by: 300, decrease_unit: "amount")

    price_1a = Bookings::CalculateStayPrice.new(
      room_type: suite, check_in: check_in, check_out: check_in + 1, rate_plan: plan, adults: 1
    ).call

    expect(price_1a).to eq(0.to_d)
  end

  # Derived offset clamping at 0
  it "a Derived offset that would take a price negative clamps at 0" do
    plan = create(:rate_plan, :custom, hotel: hotel, name: "Derived Clamp Test", ta_access: "hidden")
    save_derived_prices!(plan, suite, derive_value: -1000, derive_mode: "offset")

    price_1a = Bookings::CalculateStayPrice.new(
      room_type: suite, check_in: check_in, check_out: check_in + 1, rate_plan: plan, adults: 1
    ).call

    expect(price_1a).to eq(0.to_d)
  end

  # date price for only some adult counts
  it "a date price set for 2 adults only falls back to the list price for 3 adults that night" do
    create(:room_rate, room_type: suite, rate_plan: std_plan, date: check_in, price: 999, occupancy_prices: { "2" => "999" })

    night_2a = Rates::ResolveEffectiveNightlyPrice.call(room_type: suite, rate_plan: std_plan, date: check_in, adults: 2)
    night_3a = Rates::ResolveEffectiveNightlyPrice.call(room_type: suite, rate_plan: std_plan, date: check_in, adults: 3)

    expect(night_2a.amount).to eq(999.to_d)
    expect(night_3a.amount).to eq(600.to_d) # STD's list price for 3 adults, unaffected by the 2-adult override
  end

  # a stay across a date price, a month end and a year end
  it "a stay crossing a year boundary prices each night correctly, with a date override on one of them" do
    year_end_check_in = Date.new(Date.current.year + 1, 12, 30)
    create(:room_rate, room_type: suite, rate_plan: std_plan, date: year_end_check_in + 1, price: 700, occupancy_prices: { "2" => "700" })

    total = Bookings::CalculateStayPrice.new(
      room_type: suite, check_in: year_end_check_in, check_out: year_end_check_in + 3, rate_plan: std_plan, adults: 2
    ).call

    # nights: Dec 30 (440 list) + Dec 31 (700 override) + Jan 1 (440 list)
    expect(total).to eq((440 + 700 + 440).to_d)
  end

  # check-in = the hotel's business date, not wall-clock: late at night the
  # hotel's business day can still be "yesterday" by clock time, and a booking
  # dated for that business date should be searchable/bookable as "today" from
  # the desk's point of view even if the wall clock has already rolled over.
  it "check-in uses the hotel's business date, not the wall-clock date, for a booking made late at night" do
    late_night = Time.zone.local(Date.current.year, Date.current.month, Date.current.day, 23, 50)
    business_date = hotel.business_date_for(late_night)

    result = travel_to(late_night) do
      params = {
        room_type_id: suite.id, check_in: business_date.to_s, check_out: (business_date + 1).to_s,
        adults: 2, children: 0, rooms: 1, rate_plan_id: std_plan.id,
        rooms_detail: { "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789" } } } }
      }
      CorporatePortal::CreateAgentBooking.call(relationship: ta_a, params: params, user: ta_a_user)
    end

    expect(result).to be_success, Array(result.errors).to_sentence
    expect(result.booking.check_in.to_date).to eq(business_date)
  end

  # 2 rooms requested when only 1 is free: refused, not a partial booking
  it "requesting 2 rooms when only 1 is free is refused outright, not booked as 1" do
    single_room_type = Rooms::SaveSeedRoomType.call!(
      hotel: hotel,
      attributes: { name: "Only One", room_number_mode: "custom", quantity: 1, base_price: 150.0,
                    max_adults: 2, room_numbers: %w[O1] }
    )
    plan = single_room_type.standard_rate_plan
    plan.update!(ta_access: "all")
    save_manual_prices!(plan, single_room_type, { 1 => 150, 2 => 250 })

    result = book(
      plan: plan, room_type: single_room_type, adults: 2, rooms: 2,
      extra_rooms_detail: { "1" => { guests: { "0" => { name: "Ben Tan", phone: "+60123456780" } } } }
    )

    expect(result).not_to be_success
    expect(Array(result.errors).to_sentence).to match(/no longer has 2 rooms free/)
  end

  # two TAs racing for the last room
  it "two agents racing for the last room: the second is refused after the first books it" do
    single_room_type = Rooms::SaveSeedRoomType.call!(
      hotel: hotel,
      attributes: { name: "Last Room", room_number_mode: "custom", quantity: 1, base_price: 150.0,
                    max_adults: 2, room_numbers: %w[L1] }
    )
    plan = single_room_type.standard_rate_plan
    plan.update!(ta_access: "all")
    save_manual_prices!(plan, single_room_type, { 1 => 150, 2 => 250 })

    first = book(plan: plan, room_type: single_room_type, adults: 2, relationship: ta_a, actor: ta_a_user)
    expect(first).to be_success

    second = book(plan: plan, room_type: single_room_type, adults: 2, relationship: ta_c, actor: ta_c_user)

    expect(second).not_to be_success
  end

  # odd-cent rounding
  it "rounds a 10% discount on an odd-cent price to the cent" do
    plan = create(:rate_plan, :custom, hotel: hotel, name: "Odd Cents", ta_access: "hidden")
    save_manual_prices!(plan, suite, { 1 => 333.33, 2 => 333.33, 3 => 333.33, 4 => 333.33 })
    plan.rate_plan_stay_discounts.create!(min_nights: 3, discount_type: "percent", value: 10, from_night: 1)

    total = Bookings::CalculateStayPrice.new(
      room_type: suite, check_in: check_in, check_out: check_in + 3, rate_plan: plan, adults: 2
    ).call

    # 333.33 * 0.9 = 299.997 -> rounds to 300.00 per night
    expect(total).to eq(900.to_d)
  end

  it "rounds an amount-off discount across 3 guests to the cent" do
    plan = create(:rate_plan, :custom, hotel: hotel, name: "Odd Amount Off", ta_access: "hidden")
    save_manual_prices!(plan, suite, { 1 => 100, 2 => 100, 3 => 200, 4 => 200 })
    plan.rate_plan_stay_discounts.create!(min_nights: 2, discount_type: "amount", value: 3.33, from_night: 1)

    total = Bookings::CalculateStayPrice.new(
      room_type: suite, check_in: check_in, check_out: check_in + 2, rate_plan: plan, adults: 3
    ).call

    # 200 - (3.33 x 3 guests = 9.99) = 190.01 per night x 2
    expect(total).to eq(380.02.to_d)
  end

  # a plan archived after booking: the TA page and workspace still render
  it "an archived plan's existing booking still resolves a price and its rate plan association" do
    result = book(plan: fb_plan, adults: 2, nights: 3)
    booking = result.booking
    expect(booking.total_amount.to_d).to eq(1_350.to_d)

    fb_plan.archive!

    expect(booking.reload.booking_rooms.first.rate_plan).to eq(fb_plan)
    expect(booking.total_amount.to_d).to eq(1_350.to_d) # the booking's own total is unaffected by archiving
  end

  # currency: everything MYR
  it "every per-pax plan in the test world prices in MYR" do
    expect([ std_plan, fb_plan, corp_plan, prm_plan ].map(&:currency).uniq).to eq([ "MYR" ])
  end

  # tourism tax: Malaysian lead vs unknown-nationality lead
  it "tourism tax is 0 for a Malaysian lead and 0 (unknown) for a lead with no country given" do
    malaysian = hotel.tourism_tax_amount_for("Malaysia")
    unknown = hotel.tourism_tax_amount_for(nil)

    expect(malaysian).to eq(0.to_d)
    expect(unknown).to eq(0.to_d) # RECORDED: an unset nationality is treated the same as "not liable", not flagged as unresolved
  end

  # R10 continued: a room type whose max_adults later increases has no price for the new count
  it "R10: increasing a room type's max_adults after pricing leaves the new count unpriced" do
    suite.update!(max_adults: 5)

    price_5a = Bookings::CalculateStayPrice.new(
      room_type: suite.reload, check_in: check_in, check_out: check_in + 1, rate_plan: std_plan, adults: 5
    ).call

    expect(price_5a).to be_nil # RECORDED: R10 - raising capacity alone doesn't extend the occupancy matrix
  end
end
