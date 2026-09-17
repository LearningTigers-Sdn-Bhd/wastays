# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CorporatePortal::Bookings", type: :request do
  let(:user) { create(:user, :corporate) }
  let(:hotel) { create(:hotel, status: "live") }
  let(:relationship) { create(:hotel_corporate_account, corporate_account: user.account, hotel: hotel) }

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

  def search_params(overrides = {})
    { hotel_relationship_id: relationship.id, check_in: check_in.to_s,
      check_out: check_out.to_s, adults: 2 }.merge(overrides)
  end

  it "offers the hotels this account is linked to" do
    get new_corporate_booking_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include(hotel.name)
  end

  it "shows what is available for the dates, priced for the stay" do
    get new_corporate_booking_path(search_params)

    expect(response.body).to include("Deluxe")
    expect(response.body).to include("2 nights")
  end

  it "books a room for a guest and attributes it to the account" do
    expect {
      post corporate_bookings_path, params: {
        hotel_relationship_id: relationship.id,
        booking: {
          room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
          adults: 2, children: 0, guest_name: "Aisha Rahman", guest_phone: "+60123456789",
          guest_email: "aisha@example.com"
        }
      }
    }.to change(Booking, :count).by(1)

    booking = Booking.order(:id).last
    expect(booking.hotel_corporate_account_id).to eq(relationship.id)
    expect(booking.guest_name).to eq("Aisha Rahman")
    expect(booking.hotel_id).to eq(hotel.id)
    expect(response).to redirect_to(corporate_booking_path(booking))
  end

  # The portal is the agent's own, so a hotel they are not linked to is simply
  # not one of their choices.
  it "refuses to book a hotel this account is not linked to" do
    other = create(:hotel_corporate_account)

    expect {
      post corporate_bookings_path, params: {
        hotel_relationship_id: other.id,
        booking: { room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
                   adults: 2, guest_name: "Someone", guest_phone: "+60100000000" }
      }
    }.not_to change(Booking, :count)

    expect(response).to redirect_to(new_corporate_booking_path)
  end

  it "shows only this account's bookings" do
    mine = create(:booking, hotel: hotel, hotel_corporate_account: relationship)
    theirs = create(:booking, hotel: hotel)

    get corporate_bookings_path

    expect(response.body).to include(mine.guest_name)
    expect(response.body).not_to include(theirs.guest_name)
  end

  it "records every adult sharing the room, not just the lead" do
    post corporate_bookings_path, params: {
      hotel_relationship_id: relationship.id,
      booking: {
        room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
        adults: 2, children: 0,
        guests: {
          "0" => { name: "Aisha Rahman", phone: "+60123456789", email: "aisha@example.com" },
          "1" => { name: "Iman Rahman", phone: "+60129876543" }
        }
      }
    }

    booking = Booking.order(:id).last
    # The lead is the stay's own guest; the companion is a booking_guest on it,
    # exactly as the desk would add at check-in.
    expect(booking.guest_name).to eq("Aisha Rahman")
    expect(booking.booking_guests.count).to eq(2)
    expect(booking.guests.map(&:name)).to contain_exactly("Aisha Rahman", "Iman Rahman")
    expect(booking.booking_guests.where(is_primary: true).count).to eq(1)
  end

  it "takes the lead guest alone when the companion is not known yet" do
    post corporate_bookings_path, params: {
      hotel_relationship_id: relationship.id,
      booking: {
        room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
        adults: 2, children: 0,
        guests: {
          "0" => { name: "Aisha Rahman", phone: "+60123456789" },
          "1" => { name: "", phone: "", email: "" }
        }
      }
    }

    booking = Booking.order(:id).last
    expect(booking.guest_name).to eq("Aisha Rahman")
    expect(booking.booking_guests.count).to eq(1)
  end

  # The search is not the only gate: a stale page, or two agents confirming the
  # last room at once, both arrive straight at create.
  it "refuses to confirm a category that filled up after the search" do
    4.times do
      create(:booking, hotel: hotel, check_in: check_in, check_out: check_out, status: "confirmed").tap do |booking|
        create(:booking_room, booking: booking, room_type: room_type, room_number: nil)
      end
    end

    expect {
      post corporate_bookings_path, params: {
        hotel_relationship_id: relationship.id,
        booking: { room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
                   adults: 2, guest_name: "Late Booker", guest_phone: "+60111111111" }
      }
    }.not_to change(Booking, :count)

    expect(flash[:alert]).to include("no longer available")
  end

  it "will not sell a room that is already taken" do
    # One category, four rooms, four already sold for the same nights.
    4.times do
      create(:booking, hotel: hotel, check_in: check_in, check_out: check_out, status: "confirmed").tap do |booking|
        create(:booking_room, booking: booking, room_type: room_type, room_number: nil)
      end
    end

    get new_corporate_booking_path(search_params)

    expect(response.body).to include("Nothing is available")
  end
end
