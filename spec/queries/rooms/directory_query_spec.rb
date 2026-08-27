# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rooms::DirectoryQuery do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel:) }
  let(:other_room_type) { create(:room_type, hotel:) }

  describe ".call" do
    it "orders the numbers of a category by position" do
      create(:room, hotel:, room_type:, number: "103", position: 2)
      create(:room, hotel:, room_type:, number: "101", position: 0)
      create(:room, hotel:, room_type:, number: "102", position: 1)

      result = described_class.call(hotel:)

      expect(result.numbers_for(room_type.id)).to eq([ "101", "102", "103" ])
    end

    it "keeps each category separate" do
      create(:room, hotel:, room_type:, number: "101", position: 0)
      create(:room, hotel:, room_type: other_room_type, number: "201", position: 0)

      result = described_class.call(hotel:)

      expect(result.numbers_for(room_type.id)).to eq([ "101" ])
      expect(result.numbers_for(other_room_type.id)).to eq([ "201" ])
    end

    it "returns no numbers for a category without rooms" do
      result = described_class.call(hotel:)

      expect(result.numbers_for(room_type.id)).to eq([])
      expect(result.any?(room_type.id)).to be(false)
    end

    it "skips archived rooms" do
      create(:room, hotel:, room_type:, number: "101", position: 0)
      create(:room, hotel:, room_type:, number: "102", position: 1, archived_at: Time.current)

      result = described_class.call(hotel:)

      expect(result.numbers_for(room_type.id)).to eq([ "101" ])
      expect(result.include?(room_type.id, "102")).to be(false)
    end

    it "skips rooms of another hotel" do
      other_hotel = create(:hotel)
      other_hotel_room_type = create(:room_type, hotel: other_hotel)
      create(:room, hotel: other_hotel, room_type: other_hotel_room_type, number: "101", position: 0)

      result = described_class.call(hotel:)

      expect(result.rows).to be_empty
    end

    it "answers the room-number guard" do
      create(:room, hotel:, room_type:, number: "101", position: 0)

      result = described_class.call(hotel:)

      expect(result.include?(room_type.id, "101")).to be(true)
      expect(result.include?(room_type.id, 101)).to be(true)
      expect(result.include?(other_room_type.id, "101")).to be(false)
      expect(result.include?(room_type.id, "999")).to be(false)
    end

    it "carries the room group of each row" do
      main_wing = create(:room_group, hotel:, name: "Main Wing")
      create(:room, hotel:, room_type:, room_group: main_wing, number: "101", position: 0)
      create(:room, hotel:, room_type:, number: "102", position: 1)

      rows = described_class.call(hotel:).rows.index_by(&:number)

      expect(rows.fetch("101").room_group_id).to eq(main_wing.id)
      expect(rows.fetch("101").room_group_name).to eq("Main Wing")
      expect(rows.fetch("102").room_group_id).to be_nil
      expect(rows.fetch("102").room_group_name).to be_nil
    end

    it "reads the directory in one query" do
      create(:room, hotel:, room_type:, number: "101", position: 0)
      create(:room, hotel:, room_type: other_room_type, number: "201", position: 0)

      queries = 0
      counter = ->(*, payload) { queries += 1 unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ]) }

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        described_class.call(hotel:)
      end

      expect(queries).to eq(1)
    end
  end

  describe ".for_room_type" do
    it "lists the numbers of one category in position order" do
      create(:room, hotel:, room_type:, number: "102", position: 1)
      create(:room, hotel:, room_type:, number: "101", position: 0)

      directory = described_class.for_room_type(room_type)

      expect(directory.numbers).to eq([ "101", "102" ])
      expect(directory.include?("101")).to be(true)
      expect(directory.include?(101)).to be(true)
      expect(directory.include?("999")).to be(false)
    end

    it "skips archived rooms" do
      create(:room, hotel:, room_type:, number: "101", position: 0, archived_at: Time.current)

      expect(described_class.for_room_type(room_type).include?("101")).to be(false)
    end

    it "returns an empty directory for a category that is not saved" do
      directory = described_class.for_room_type(RoomType.new)

      expect(directory.numbers).to eq([])
      expect(directory.any?).to be(false)
    end

    it "returns an empty directory when no category is given" do
      expect(described_class.for_room_type(nil).numbers).to eq([])
    end
  end
end
