# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "HotelPortal::RoomLocks", type: :request do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }

  before do
    create(:user_hotel_access, user: user, hotel: hotel)
    post login_path, params: { email: user.email, password: "password123" }
  end

  describe "POST /create" do
    it "creates a new lock" do
      expect {
        post hotel_room_locks_path(hotel), params: { room_number: "206" }
      }.to change(RoomLock, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["status"]).to eq("success")
    end

    it "refreshes an existing lock by the same user" do
      lock = create(:room_lock, hotel: hotel, user: user, room_number: "206", expires_at: 1.minute.from_now)

      post hotel_room_locks_path(hotel), params: { room_number: "206" }

      expect(response).to have_http_status(:ok)
      expect(lock.reload.expires_at).to be > 5.minutes.from_now
    end

    it "returns conflict if locked by someone else" do
      other_user = create(:user, name: "Other Admin")
      create(:room_lock, hotel: hotel, user: other_user, room_number: "206")

      post hotel_room_locks_path(hotel), params: { room_number: "206" }

      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)["message"]).to include("Other Admin")
    end
  end

  describe "DELETE /release" do
    it "releases the lock" do
      create(:room_lock, hotel: hotel, user: user, room_number: "206")

      expect {
        delete release_hotel_room_locks_path(hotel), params: { room_number: "206" }
      }.to change(RoomLock, :count).by(-1)

      expect(response).to have_http_status(:ok)
    end
  end
end
