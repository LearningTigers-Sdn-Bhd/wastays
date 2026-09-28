# frozen_string_literal: true

require "rails_helper"

# Test plan phase D: date prices and restrictions.
# docs/wastays/per-pax-ta-reservations-test-plan-2026-09-25.md §7.4.
RSpec.describe "Per-pax date prices and restrictions" do
  include_context "per-pax resort"

  let(:check_in) { Date.current + 10 }

  # D1: FB Suite, night 2 date price occupancy_prices {"2" => 600}, 2A, 3 nights
  it "D1: a date-specific occupancy price replaces the list price for that one night, discount applied after" do
    create(:room_rate, room_type: suite, rate_plan: fb_plan, date: check_in + 1, price: 600,
                        occupancy_prices: { "2" => "600" })

    total = Bookings::CalculateStayPrice.new(
      room_type: suite, check_in: check_in, check_out: check_in + 3, rate_plan: fb_plan, adults: 2
    ).call

    # nights: 500, 600, 500 -> 10% off each (>=3 rule) -> 450 + 540 + 450
    expect(total).to eq(1_440.to_d)
  end

  # D2: same with a child 8, ages given - the date price only sets occupancy
  # for 2 adults, so the child's band falls back to the plan's 1-adult list
  # price (300), not that night's per-adult share.
  it "D2: night 2 child (with age given) prices off the 1-adult list price when the date sets none" do
    create(:room_rate, room_type: suite, rate_plan: fb_plan, date: check_in + 1, price: 600,
                        occupancy_prices: { "2" => "600" })

    night2 = Rates::ResolveEffectiveNightlyPrice.call(
      room_type: suite, rate_plan: fb_plan, date: check_in + 1, adults: 2, children: 1, child_ages: [ 8 ]
    )

    # adult total 600, child = 40% of the 1-adult list price 300 = 120
    expect(night2.amount).to eq(720.to_d)
  end

  it "D2b: a date price for 1 adult becomes the child's band anchor that night" do
    create(:room_rate, room_type: suite, rate_plan: fb_plan, date: check_in + 1, price: 600,
                        occupancy_prices: { "1" => "400", "2" => "600" })

    night2 = Rates::ResolveEffectiveNightlyPrice.call(
      room_type: suite, rate_plan: fb_plan, date: check_in + 1, adults: 2, children: 1, child_ages: [ 8 ]
    )

    # adult total 600, child = 40% of that night's 1-adult 400 = 160
    expect(night2.amount).to eq(760.to_d)
  end

  # D3: same with no age given (fallback multiplier)
  it "D3: night 2 child with no ages given is a full per-adult share of that night: 600/2 = 300" do
    create(:room_rate, room_type: suite, rate_plan: fb_plan, date: check_in + 1, price: 600,
                        occupancy_prices: { "2" => "600" })

    night2 = Rates::ResolveEffectiveNightlyPrice.call(
      room_type: suite, rate_plan: fb_plan, date: check_in + 1, adults: 2, children: 1, child_ages: []
    )

    expect(night2.amount).to eq(900.to_d) # 600 (adults) + 300 (child @ full per-adult share)
  end

  describe "R8: TA search and booking honour stop-sell, stay length and closed-to-arrival/departure" do
    def fb_option_for(check_out)
      CorporatePortal::AgentStaySearch.call(
        hotel: hotel, check_in: check_in, check_out: check_out, adults: 2, relationship: ta_a
      ).options.find { |o| o.rate_plan == fb_plan && o.room_type == suite }
    end

    it "D4: a stop-sell night refuses the desk and shows the TA the plan as not bookable" do
      create(:room_rate, room_type: suite, rate_plan: fb_plan, date: check_in + 1, price: 500, stop_sell: true)

      desk_options = Bookings::RateOptions.new(
        room_type: suite, check_in: check_in, check_out: check_in + 3, apply_stop_sell: true
      ).call
      expect(desk_options.find { |o| o[:id] == fb_plan.id }).to be_blank

      fb_option = fb_option_for(check_in + 3)
      expect(fb_option).not_to be_available
      expect(fb_option.restriction).to eq("Closed for sale on #{(check_in + 1).strftime('%-d %b')}")
    end

    it "D5: a stay under the plan's minimum refuses the desk and the TA" do
      create(:room_rate, room_type: suite, rate_plan: fb_plan, date: check_in, price: 500, min_stay: 3)

      desk_options = Bookings::RateOptions.new(
        room_type: suite, check_in: check_in, check_out: check_in + 2, apply_stay_length: true
      ).call
      expect(desk_options.find { |o| o[:id] == fb_plan.id }).to be_blank

      fb_option = fb_option_for(check_in + 2)
      expect(fb_option).not_to be_available
      expect(fb_option.restriction).to eq("Minimum stay 3 nights")
      expect(fb_option_for(check_in + 3)).to be_available
    end

    it "D6: closed to arrival on the check-in date refuses the desk and the TA" do
      create(:room_rate, room_type: suite, rate_plan: fb_plan, date: check_in, price: 500, closed_to_arrival: true)

      desk_options = Bookings::RateOptions.new(
        room_type: suite, check_in: check_in, check_out: check_in + 2, apply_arrival_departure: true
      ).call
      expect(desk_options.find { |o| o[:id] == fb_plan.id }).to be_blank

      fb_option = fb_option_for(check_in + 2)
      expect(fb_option).not_to be_available
      expect(fb_option.restriction).to eq("No arrivals on #{check_in.strftime('%-d %b')}")
    end

    it "D7: closed to departure on the check-out date refuses the desk and the TA" do
      create(:room_rate, room_type: suite, rate_plan: fb_plan, date: check_in + 2, price: 500, closed_to_departure: true)

      desk_options = Bookings::RateOptions.new(
        room_type: suite, check_in: check_in, check_out: check_in + 2, apply_arrival_departure: true
      ).call
      expect(desk_options.find { |o| o[:id] == fb_plan.id }).to be_blank

      fb_option = fb_option_for(check_in + 2)
      expect(fb_option).not_to be_available
      expect(fb_option.restriction).to eq("No departures on #{(check_in + 2).strftime('%-d %b')}")
    end

    it "leaves other plans on the same dates bookable" do
      create(:room_rate, room_type: suite, rate_plan: fb_plan, date: check_in + 1, price: 500, stop_sell: true)

      prm_option = CorporatePortal::AgentStaySearch.call(
        hotel: hotel, check_in: check_in, check_out: check_in + 3, adults: 2, relationship: ta_a
      ).options.find { |o| o.rate_plan == prm_plan && o.room_type == suite }

      expect(prm_option).to be_available
    end

    it "R8 (booking, not just search): CreateAgentBooking refuses a stop-sell night" do
      create(:room_rate, room_type: suite, rate_plan: fb_plan, date: check_in + 1, price: 500, stop_sell: true)

      params = {
        room_type_id: suite.id, check_in: check_in.to_s, check_out: (check_in + 3).to_s,
        adults: 2, children: 0, rooms: 1, rate_plan_id: fb_plan.id,
        rooms_detail: { "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789" } } } }
      }
      result = nil
      expect {
        result = CorporatePortal::CreateAgentBooking.call(relationship: ta_a, params: params, user: ta_a_user)
      }.not_to change(Booking, :count)

      expect(result).not_to be_success
      expect(result.errors).to eq([ "Full Board can't be booked for these dates: Closed for sale on #{(check_in + 1).strftime('%-d %b')}." ])
    end
  end
end
