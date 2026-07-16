# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V2::Bookings", type: :request do
  let(:hotel) { create(:hotel) }
  let(:api_key) { create(:api_key, bearer: hotel) }
  let(:headers) { { "Authorization" => "Bearer #{api_key.token}" } }
  let(:room_type) { create(:room_type, hotel:) }

  describe "GET /api/v2/bookings/:id" do
    it "wraps an ungrouped booking as a one-child reservation" do
      booking = create(:booking, hotel:, guest_name: "Primary Guest")
      room = create(:booking_room, booking:, room_type:, room_number: "101")

      get api_v2_booking_path(booking.confirmation_token), headers: headers

      expect(response).to have_http_status(:ok)
      payload = response.parsed_body
      expect(payload["api_version"]).to eq("v2")
      expect(payload.dig("reservation", "identity")).to include(
        "type" => "booking", "id" => booking.id, "confirmation_token" => booking.confirmation_token
      )
      expect(payload.dig("reservation", "group")).to be_nil
      expect(payload.dig("reservation", "bookings").size).to eq(1)
      expect(payload.dig("reservation", "bookings", 0, "room")).to include(
        "id" => room.id, "room_number" => "101"
      )
      expect(payload.dig("reservation", "guest_name")).to eq("Primary Guest")
    end

    it "returns the group-first reservation for child and group identities" do
      group = create(:group_booking, hotel:, external_reference: "EXT-GROUP-42")
      first = create(:booking, hotel:, group_booking: group, group_position: 1)
      second = create(:booking, hotel:, group_booking: group, group_position: 2)
      first_room = create(:booking_room, booking: first, room_type:, room_number: "201")
      second_room = create(:booking_room, booking: second, room_type:, room_number: "202")

      [ first.id, first.confirmation_token, "group-#{group.id}", group.confirmation_token,
        group.formatted_reservation_number, group.external_reference ].each do |identifier|
        get api_v2_booking_path(identifier), headers: headers

        expect(response).to have_http_status(:ok)
        reservation = response.parsed_body.fetch("reservation")
        expect(reservation.fetch("identity")).to include(
          "type" => "group_booking", "id" => group.id, "confirmation_token" => group.confirmation_token
        )
        expect(reservation.fetch("group")).to include("id" => group.id, "name" => group.name)
        expect(reservation.fetch("bookings").pluck("id")).to eq([ first.id, second.id ])
        expect(reservation.fetch("bookings").map { |child| child.dig("room", "id") }).to eq([ first_room.id, second_room.id ])
      end
    end


    it "uses a typed group id when booking and group numeric ids collide" do
      unrelated = create(:booking, hotel:)
      create(:booking_room, booking: unrelated, room_type:)
      group = create(:group_booking, id: unrelated.id, hotel:)
      child = create(:booking, hotel:, group_booking: group, group_position: 1)
      create(:booking_room, booking: child, room_type:)

      get api_v2_booking_path("group-#{group.id}"), headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("reservation", "identity")).to include(
        "type" => "group_booking", "id" => group.id, "lookup" => "group-#{group.id}"
      )
    end

    it "includes legacy split identifiers when lineage exists" do
      group = create(:group_booking, hotel:)
      legacy = create(:booking, hotel:, group_booking: group, group_position: 1)
      child = create(:booking, hotel:, group_booking: group, group_position: 2)
      legacy_room = create(:booking_room, booking: legacy, room_type:)
      child_room = create(:booking_room, booking: child, room_type:)
      batch_id = SecureRandom.uuid
      create(:legacy_booking_split_lineage, legacy_booking: legacy, group_booking: group,
        child_booking: legacy, booking_room: legacy_room, anchor: true, batch_id:)
      create(:legacy_booking_split_lineage, legacy_booking: legacy, group_booking: group,
        child_booking: child, booking_room: child_room, anchor: false, batch_id:)

      get api_v2_booking_path(group.confirmation_token), headers: headers

      legacy_payload = response.parsed_body.dig("reservation", "legacy")
      expect(legacy_payload).to include(
        "legacy_booking_id" => legacy.id,
        "legacy_confirmation_token" => legacy.confirmation_token,
        "split_batch_id" => batch_id
      )
      expect(legacy_payload.fetch("lineages").pluck("child_booking_id")).to contain_exactly(legacy.id, child.id)
    end

    it "uses v1 authentication and booking authorization scope" do
      other_booking = create(:booking)
      create(:booking_room, booking: other_booking, room_type: create(:room_type, hotel: other_booking.hotel))

      get api_v2_booking_path(other_booking), headers: headers
      expect(response).to have_http_status(:not_found)

      get api_v2_booking_path(other_booking)
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
