# frozen_string_literal: true

require "rails_helper"

RSpec.describe Room, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:hotel) }
    it { is_expected.to belong_to(:room_type) }
    it { is_expected.to belong_to(:room_group).optional }
  end

  describe "validations" do
    it "strips the room number and enforces hotel-wide uniqueness" do
      hotel = create(:hotel)
      first_type = create(:room_type, hotel:)
      second_type = create(:room_type, hotel:)
      create(:room, hotel:, room_type: first_type, number: " 101 ")

      duplicate = build(:room, hotel:, room_type: second_type, number: "101")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:number]).to include("has already been taken")
      expect(hotel.rooms.sole.number).to eq("101")
    end

    it "uses case-sensitive room-number uniqueness" do
      hotel = create(:hotel)
      room_type = create(:room_type, hotel:)
      create(:room, hotel:, room_type:, number: "A101")

      expect(build(:room, hotel:, room_type:, number: "a101")).to be_valid
    end

    it "allows the same room number in different hotels" do
      first_type = create(:room_type)
      second_type = create(:room_type)
      create(:room, hotel: first_type.hotel, room_type: first_type, number: "101")

      expect(build(:room, hotel: second_type.hotel, room_type: second_type, number: "101")).to be_valid
    end

    it "requires the room type to belong to the hotel" do
      room = build(:room, hotel: create(:hotel), room_type: create(:room_type))

      expect(room).not_to be_valid
      expect(room.errors[:room_type]).to include("must belong to the same hotel")
    end

    it "requires the optional room group to belong to the hotel" do
      room_type = create(:room_type)
      room = build(:room, hotel: room_type.hotel, room_type:, room_group: create(:room_group))

      expect(room).not_to be_valid
      expect(room.errors[:room_group]).to include("must belong to the same hotel")
    end

    it "requires a nonnegative integer position" do
      expect(build(:room, position: -1)).not_to be_valid
      expect(build(:room, position: 1.5)).not_to be_valid
    end

    it "allows the room number to change, because Rooms::Rename carries the history" do
      room = create(:room)

      room.number = "NEW-101"

      expect(room).to be_valid
    end

    it "does not allow the room type to change" do
      room = create(:room)
      room.room_type = create(:room_type, hotel: room.hotel)

      expect(room).not_to be_valid
      expect(room.errors[:room_type]).to include("cannot be changed")
    end

    it "rejects untrimmed numbers at the database boundary" do
      room_type = create(:room_type)
      attributes = {
        hotel_id: room_type.hotel_id,
        room_type_id: room_type.id,
        position: 0,
        created_at: Time.current,
        updated_at: Time.current
      }

      expect { described_class.insert_all!([ attributes.merge(number: " 101 ") ]) }
        .to raise_error(ActiveRecord::StatementInvalid, /rooms_number_normalized/)
    end

    it "rejects blank numbers at the database boundary" do
      room_type = create(:room_type)
      attributes = {
        hotel_id: room_type.hotel_id,
        room_type_id: room_type.id,
        position: 0,
        created_at: Time.current,
        updated_at: Time.current
      }

      expect { described_class.insert_all!([ attributes.merge(number: "") ]) }
        .to raise_error(ActiveRecord::StatementInvalid, /rooms_number_normalized/)
    end
  end

  describe "scopes" do
    it "separates active and archived rooms and orders by position" do
      hotel = create(:hotel)
      room_type = create(:room_type, hotel:)
      second = create(:room, hotel:, room_type:, position: 2)
      first = create(:room, hotel:, room_type:, position: 1)
      archived = create(:room, hotel:, room_type:, archived_at: Time.current)

      expect(described_class.active.ordered).to eq([ first, second ])
      expect(described_class.archived).to contain_exactly(archived)
    end
  end

  describe "archive state" do
    it "archives and restores the same room record" do
      room = create(:room)

      expect(room).to be_active
      expect(room.archive!).to eq(room)
      expect(room).to be_archived
      expect(room.restore!).to eq(room)
      expect(room).to be_active
    end
  end
end
