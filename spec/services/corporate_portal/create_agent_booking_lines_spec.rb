# frozen_string_literal: true

require "rails_helper"

# An agent's stay can mix categories, rates and parties, on one set of dates.
RSpec.describe CorporatePortal::CreateAgentBooking, "with several lines" do
  include_context "per-pax resort"

  let(:check_in) { Date.current + 20 }

  def lead(name) = { guests: { "0" => { name: name, phone: "+60123456789" } } }

  def book(lines:, detail:, relationship: ta_a, actor: ta_a_user)
    described_class.call(
      relationship: relationship, user: actor,
      params: { check_in: check_in.to_s, check_out: (check_in + 1).to_s, lines: lines, rooms_detail: detail }
    )
  end

  let(:two_lines) do
    {
      "0" => { room_type_id: suite.id, rate_plan_id: std_plan.id, adults: 3, children: 0, quantity: 1 },
      "1" => { room_type_id: twin.id, rate_plan_id: fb_plan.id, adults: 2, children: 0, quantity: 2 }
    }
  end
  let(:three_leads) { { "0" => lead("Ada"), "1" => lead("Bo"), "2" => lead("Cy") } }

  it "books each room in its own category, on its own rate, for its own party" do
    result = book(lines: two_lines, detail: three_leads)

    expect(result).to be_success
    bookings = result.bookings
    expect(bookings.map(&:guest_name)).to eq(%w[Ada Bo Cy])
    expect(bookings.map { |booking| booking.booking_rooms.first.room_type }).to eq([ suite, twin, twin ])
    expect(bookings.map { |booking| booking.booking_rooms.first.rate_plan }).to eq([ std_plan, fb_plan, fb_plan ])
    expect(bookings.map(&:adults)).to eq([ 3, 2, 2 ])
    expect(bookings.map { |booking| booking.total_amount.to_d }).to eq([ 600, 430, 430 ])
  end

  it "puts every room in one group, on the same dates" do
    result = book(lines: two_lines, detail: three_leads)

    expect(result.group_booking).to be_present
    expect(result.bookings.map(&:group_booking_id).uniq).to eq([ result.group_booking.id ])
    expect(result.bookings.map { |booking| [ booking.check_in.to_date, booking.check_out.to_date ] }.uniq).to eq([ [ check_in, check_in + 1 ] ])
  end

  it "attributes every room to the agent, the same as a single-category stay" do
    result = book(lines: two_lines, detail: three_leads)

    expect(result.bookings.map(&:source).uniq).to eq([ "travel_agent" ])
    expect(result.bookings.map(&:hotel_corporate_account_id).uniq).to eq([ ta_a.id ])
    expect(result.bookings.map(&:corporate_booked_by_id).uniq).to eq([ ta_a_user.id ])
  end

  it "asks for a lead for every room across all lines" do
    result = book(lines: two_lines, detail: { "0" => lead("Ada"), "1" => lead("Bo") })

    expect(result).not_to be_success
    expect(result.errors).to eq([ "Name the lead guest for room 3." ])
    expect(Booking.count).to eq(0)
  end

  it "books nothing when one line cannot be had" do
    lines = two_lines.merge("1" => two_lines["1"].merge(quantity: 3)) # the twin has two rooms

    expect { book(lines: lines, detail: { "0" => lead("A"), "1" => lead("B"), "2" => lead("C"), "3" => lead("D") }) }
      .not_to change(Booking, :count)
  end

  it "refuses a line on a rate this agency is not offered, and books nothing" do
    result = nil
    expect { result = book(lines: two_lines, detail: three_leads, relationship: ta_b, actor: ta_b_user) }.not_to change(Booking, :count)

    expect(result.errors).to include("Choose a rate plan.")
  end

  it "prices each line for its own children, by age" do
    lines = { "0" => { room_type_id: suite.id, rate_plan_id: fb_plan.id, adults: 2, children: 1, child_ages: "6", quantity: 1 },
              "1" => { room_type_id: suite.id, rate_plan_id: fb_plan.id, adults: 2, children: 0, quantity: 1 } }

    result = book(lines: lines, detail: { "0" => lead("A"), "1" => lead("B") })

    expect(result).to be_success
    expect(result.bookings.map(&:children)).to eq([ 1, 0 ])
    expect(result.bookings.first.total_amount.to_d).to be > result.bookings.last.total_amount.to_d
  end

  it "still books the older single-category shape" do
    result = described_class.call(
      relationship: ta_a, user: ta_a_user,
      params: { room_type_id: suite.id, rate_plan_id: std_plan.id, check_in: check_in.to_s, check_out: (check_in + 1).to_s,
                adults: 2, children: 0, rooms: 2, rooms_detail: { "0" => lead("A"), "1" => lead("B") } }
    )

    expect(result).to be_success
    expect(result.bookings.size).to eq(2)
  end
end
