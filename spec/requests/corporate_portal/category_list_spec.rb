# frozen_string_literal: true

require "rails_helper"

# The wizard lists the categories that have rooms free before it knows who is in
# them. A category that sells only from two adults up (no one-adult price) must
# still be listed.
RSpec.describe "Corporate portal booking wizard: room category list", type: :request do
  include_context "per-pax resort"

  let(:check_in) { Date.current + 20 }

  def listed_categories
    get new_corporate_booking_path(hotel_relationship_id: ta_a.id, check_in: check_in.to_s, check_out: (check_in + 1).to_s, step: "rooms")
    Capybara.string(response.body).all("[data-testid='agent-room-type'] p.font-bold").map { |node| node.text.strip }
  end

  before { sign_in_as(ta_a_user) }

  it "lists every category that has rooms free" do
    expect(listed_categories).to contain_exactly(suite.name, twin.name)
  end

  it "still lists a category that has no one-adult price on any rate" do
    RoomTypeRatePlanOccupancyPrice.joins(:room_type_rate_plan)
                                  .where(room_type_rate_plans: { room_type_id: twin.id }, adults: 1).delete_all

    expect(listed_categories).to contain_exactly(suite.name, twin.name)
  end

  it "does not list a category with nothing free" do
    twin.rooms.each do |room|
      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: check_in, check_out: check_in + 1)
      create(:booking_room, booking: booking, room_type: twin, room_number: room.number)
    end

    expect(listed_categories).to eq([ suite.name ])
  end
end
