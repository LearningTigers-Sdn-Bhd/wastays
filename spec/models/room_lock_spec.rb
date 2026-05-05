# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RoomLock, type: :model do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }

  it "is valid with valid attributes" do
    lock = RoomLock.new(hotel: hotel, user: user, room_number: "206", expires_at: 10.minutes.from_now)
    expect(lock).to be_valid
  end

  it "is invalid without a room number" do
    lock = RoomLock.new(room_number: nil)
    expect(lock).not_to be_valid
  end

  it "is invalid if room is already locked in same hotel" do
    create(:room_lock, hotel: hotel, room_number: "206", expires_at: 10.minutes.from_now)
    lock = RoomLock.new(hotel: hotel, user: user, room_number: "206", expires_at: 10.minutes.from_now)
    expect(lock).not_to be_valid
    expect(lock.errors[:room_number]).to include("is currently being assigned by another staff member")
  end

  it "is valid if same room is locked in different hotel" do
    create(:room_lock, hotel: create(:hotel), room_number: "206", expires_at: 10.minutes.from_now)
    lock = RoomLock.new(hotel: hotel, user: user, room_number: "206", expires_at: 10.minutes.from_now)
    expect(lock).to be_valid
  end

  describe ".cleanup_expired!" do
    it "removes expired locks" do
      create(:room_lock, expires_at: 1.minute.ago)
      create(:room_lock, expires_at: 1.minute.from_now)

      expect { RoomLock.cleanup_expired! }.to change { RoomLock.count }.by(-1)
    end
  end

  describe "#refresh!" do
    it "extends the expiration time" do
      lock = create(:room_lock, expires_at: 1.minute.from_now)
      original_expiry = lock.expires_at

      lock.refresh!(20.minutes)
      expect(lock.expires_at).to be > original_expiry + 15.minutes
    end
  end
end
