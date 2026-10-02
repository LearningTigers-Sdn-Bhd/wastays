# frozen_string_literal: true

require "rails_helper"

# Children's ages reach the price from the travel agent portal and the desk,
# not only the public site, and are kept on the booking so later re-pricing
# stays on the age band. FB: 2A 500, 1A 300, Child 4-11 at 40% of the 1-adult
# price -> 2A + child 8 = 620 a night, 10% off every night from 3 nights.
RSpec.describe "Per-pax child ages across channels", frozen_time: :business_day, type: :request do
  include_context "per-pax resort"

  let(:check_in) { Date.current + 20 }

  describe "travel agent portal" do
    before { sign_in_as(ta_a_user) }

    it "quotes the child by age, and carries the ages into the booking form" do
      get new_corporate_booking_path(hotel_relationship_id: ta_a.id, check_in: check_in, check_out: check_in + 3, step: "rooms",
                                     stage: "rate", add_room_type_id: suite.id, add_adults: 2, add_children: 1,
                                     add_child_ages: "8", add_quantity: 1)

      page = Nokogiri::HTML(response.body)
      # 1,674 room total before tax; SST is folded into the figure shown.
      option = CorporatePortal::AgentStaySearch.call(
        hotel: hotel, check_in: check_in, check_out: check_in + 3, adults: 2, children: 1, child_ages: [ 8 ],
        relationship: ta_a
      ).options.find { |candidate| candidate.room_type == suite && candidate.rate_plan == fb_plan }
      expect(page.text).to include(ActiveSupport::NumberHelper.number_to_rounded(option.total_amount, precision: 2, delimiter: ","))

      get new_corporate_booking_path(hotel_relationship_id: ta_a.id, check_in: check_in, check_out: check_in + 3, step: "guests",
                                     lines: { "0" => { room_type_id: suite.id, rate_plan_id: fb_plan.id, adults: 2, children: 1,
                                                        child_ages: "8", quantity: 1 } })

      form = Nokogiri::HTML(response.body)
      expect(form.at_css("input[name='booking[lines][0][child_ages]']")["value"]).to eq("8")
    end

    it "tells the agent which category cannot hold the party" do
      get new_corporate_booking_path(hotel_relationship_id: ta_a.id, check_in: check_in, check_out: check_in + 1, step: "rooms",
                                     stage: "rate", add_room_type_id: twin.id, add_adults: 2, add_children: 2, add_child_ages: "5,6")

      expect(response.body).to include("Pax Deluxe Twin holds up to 2 adults and 1 child.")
    end

    it "books the child at the age-band price and keeps the age on the booking" do
      post corporate_bookings_path, params: {
        hotel_relationship_id: ta_a.id,
        booking: {
          room_type_id: suite.id, rate_plan_id: fb_plan.id, check_in: check_in, check_out: check_in + 3,
          adults: 2, children: 1, child_ages: [ "8" ], rooms: 1,
          rooms_detail: { "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789" } } } }
        }
      }

      booking = Booking.order(:id).last
      expect(booking.booking_rooms.sole.subtotal).to eq(1_674.to_d)
      expect(booking.child_ages).to eq([ 8 ])
    end
  end

  describe "front desk" do
    let(:user) { create(:user) }
    let(:role) { create(:role, account: hotel.account) }

    before do
      %w[manage_bookings view_bookings].each do |slug|
        permission = Permission.find_by(slug: slug) || create(:permission, slug: slug, name: slug.titleize)
        create(:role_permission, role: role, permission: permission)
      end
      create(:user_hotel_access, user: user, hotel: hotel, role: role)
      BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.current)
      sign_in_as(user)
    end

    it "asks for children's ages on each room row of a per-guest property" do
      get room_row_hotel_bookings_path(hotel), params: { index: "2" }

      row = Nokogiri::HTML(response.body).at_css("[data-controller='child-ages']")
      expect(row["data-child-ages-name-value"]).to eq("booking[rooms][2][child_ages][]")
      expect(row.at_css("[data-role='child-ages'] [data-child-ages-target='list']")).to be_present
    end

    it "quotes the child by age in the live price" do
      get stay_price_hotel_bookings_path(hotel), params: {
        room_type_id: suite.id, rate_plan_id: fb_plan.id, check_in: check_in.iso8601, check_out: (check_in + 3).iso8601,
        adults: 2, children: 1, child_ages: [ "8" ]
      }

      expect(response.parsed_body["room_total"].to_d).to eq(1_674.to_d)
    end

    it "flags, without refusing, a party the room is not meant to hold" do
      get stay_price_hotel_bookings_path(hotel), params: {
        room_type_id: twin.id, rate_plan_id: std_plan.id, check_in: check_in.iso8601, check_out: (check_in + 1).iso8601,
        adults: 2, children: 2
      }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["occupancy_warning"]).to eq("Pax Deluxe Twin holds up to 2 adults and 1 child.")
      expect(response.parsed_body["room_total"].to_d).to be_positive
    end

    it "books the child at the age-band price and keeps the age on the booking" do
      post hotel_booking_action_new_booking_path(hotel), params: {
        booking: {
          guest_name: "Ben Tan", guest_phone: "+60123456780", guest_gender: "male",
          check_in: check_in, check_out: check_in + 3, booking_type: "reservation",
          rooms: { "0" => { room_type_id: suite.id, rate_plan_id: fb_plan.id, adults: 2, children: 1, child_ages: [ "8" ] } }
        }
      }

      booking = Booking.order(:id).last
      expect(booking.booking_rooms.sole.subtotal).to eq(1_674.to_d)
      expect(booking.child_ages).to eq([ 8 ])
    end
  end
end
