# frozen_string_literal: true

require "rails_helper"

# Which rate plans a travel agent is offered is the property's call, made per
# plan in the rate plan editor (RatePlan#ta_access).
RSpec.describe "CorporatePortal rate plan access", type: :request do
  let(:user) { create(:user, :corporate) }
  let(:hotel) { create(:hotel, status: "live") }
  let(:relationship) do
    create(:hotel_corporate_account, corporate_account: user.account, hotel: hotel, agent_booking_enabled: true)
  end
  let(:other_agency) { create(:hotel_corporate_account, hotel: hotel, agent_booking_enabled: true) }

  let!(:room_type) do
    Rooms::SaveSeedRoomType.call!(
      hotel: hotel,
      attributes: { name: "Deluxe", room_number_mode: "custom", quantity: 4, base_price: 250.0,
                    max_adults: 3, max_children: 2, room_numbers: %w[101 102 103 104] }
    )
  end
  let(:check_in) { Date.current + 14 }
  let(:check_out) { Date.current + 16 }

  before do
    relationship
    sign_in_as(user)
  end

  def full_board(ta_access:, agencies: [])
    plan = create(:rate_plan, :custom, hotel: hotel, name: "TA Full Board", ta_access: ta_access)
    create(:room_type_rate_plan, rate_plan: plan, room_type: room_type, pricing_value: 400)
    agencies.each { |agency| plan.rate_plan_agency_rules.create!(hotel_corporate_account: agency) }
    plan
  end

  def offered_plan_names
    get new_corporate_booking_path(hotel_relationship_id: relationship.id, check_in: check_in.to_s,
                                   check_out: check_out.to_s, adults: 2)
    response.parsed_body.css("li").map(&:text).grep(/Deluxe/).map(&:squish)
  end

  def book(rate_plan_id:)
    post corporate_bookings_path, params: {
      hotel_relationship_id: relationship.id,
      booking: {
        room_type_id: room_type.id, rate_plan_id: rate_plan_id, check_in: check_in.to_s, check_out: check_out.to_s,
        adults: 2, children: 0, rooms: 1,
        rooms_detail: { "0" => { guests: { "0" => { name: "Aisha Rahman", phone: "+60123456789" } } } }
      }
    }
  end

  it "offers only the Corporate Rate until the property opens another plan" do
    full_board(ta_access: "hidden")

    names = offered_plan_names
    expect(names.size).to eq(1)
    expect(names.first).to include("Corporate Rate")
  end

  it "offers every plan opened to all agents as its own choice" do
    full_board(ta_access: "all")

    expect(offered_plan_names).to contain_exactly(a_string_including("Corporate Rate"), a_string_including("TA Full Board"))
  end

  it "hides a plan from an excluded agency and shows it to the rest" do
    full_board(ta_access: "except", agencies: [ relationship ])
    expect(offered_plan_names.join).not_to include("TA Full Board")

    full_board(ta_access: "except", agencies: [ other_agency ]).update!(name: "TA Half Board")
    expect(offered_plan_names.join).to include("TA Half Board")
  end

  it "shows an only-these plan to the named agency alone" do
    full_board(ta_access: "only", agencies: [ other_agency ])
    expect(offered_plan_names.join).not_to include("TA Full Board")

    full_board(ta_access: "only", agencies: [ relationship ]).update!(name: "TA Half Board")
    expect(offered_plan_names.join).to include("TA Half Board")
  end

  it "books the plan the agent chose" do
    plan = full_board(ta_access: "all")

    expect { book(rate_plan_id: plan.id) }.to change(Booking, :count).by(1)
    expect(Booking.last.booking_rooms.sole.rate_plan_id).to eq(plan.id)
  end

  it "refuses a plan that is hidden from this agency, even when its id is submitted" do
    plan = full_board(ta_access: "only", agencies: [ other_agency ])

    expect { book(rate_plan_id: plan.id) }.not_to change(Booking, :count)
    expect(flash[:alert]).to include("Choose a rate plan")
  end
end
