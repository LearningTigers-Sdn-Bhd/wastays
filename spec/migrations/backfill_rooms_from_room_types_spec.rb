# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260826131000_backfill_rooms_from_room_types")

RSpec.describe BackfillRoomsFromRoomTypes do
  subject(:migration) { described_class.new }

  it "backfills valid room numbers with positions and inherited groups" do
    hotel = create(:hotel)
    group = create(:room_group, hotel:)
    room_type = create(:room_type, hotel:, room_group: group, quantity: 2, room_numbers: [])
    quantity_only = create(:room_type, hotel:, quantity: 3, room_numbers: [])
    room_type.update_column(:room_numbers, [ "101", "102" ])
    Room.where(hotel:).delete_all

    ActiveRecord::Migration.suppress_messages { migration.up }

    expect(Room.where(room_type:).order(:position).pluck(:number, :position, :room_group_id)).to eq([
      [ "101", 0, group.id ],
      [ "102", 1, group.id ]
    ])
    expect(Room.where(room_type: quantity_only)).to be_empty
  end

  it "can run again without creating duplicate rooms" do
    room_type = create(:room_type, quantity: 1, room_numbers: [ "101" ])
    Room.where(hotel: room_type.hotel).delete_all

    ActiveRecord::Migration.suppress_messages do
      migration.up
      migration.up
    end

    expect(Room.where(hotel: room_type.hotel, number: "101").count).to eq(1)
  end

  it "flattens nested legacy room-number lists" do
    room_type = create(:room_type, quantity: 2, room_numbers: [])
    room_type.update_column(:room_numbers, [ [ "101", "102" ] ])
    Room.where(hotel: room_type.hotel).delete_all

    ActiveRecord::Migration.suppress_messages { migration.up }

    expect(Room.where(room_type:).order(:position).pluck(:number, :position)).to eq([
      [ "101", 0 ],
      [ "102", 1 ]
    ])
  end

  it "removes shadow rows during rollback while JSON remains authoritative" do
    room_type = create(:room_type, quantity: 1, room_numbers: [ "101" ])
    Room.where(hotel: room_type.hotel).delete_all
    ActiveRecord::Migration.suppress_messages { migration.up }

    ActiveRecord::Migration.suppress_messages { migration.down }

    expect(Room.count).to eq(0)
    expect(room_type.reload.room_numbers).to eq([ "101" ])
  end

  it "reports hotel-wide collisions before it inserts rooms" do
    hotel = create(:hotel)
    first = create(:room_type, hotel:, name: "Deluxe", quantity: 1, room_numbers: [ "101" ])
    second = create(:room_type, hotel:, name: "Suite", quantity: 1, room_numbers: [])
    second.update_column(:room_numbers, [ "101" ])
    Room.where(hotel:).delete_all

    expect { ActiveRecord::Migration.suppress_messages { migration.up } }
      .to raise_error(ActiveRecord::MigrationError, /hotel #{hotel.id}.*room "101".*#{first.id}.*#{second.id}.*Correct every finding/m)
    expect(Room.where(hotel:)).to be_empty
  end

  {
    "blank room numbers" => [ "101", " " ],
    "untrimmed room numbers" => [ " 101 ", "102" ],
    "duplicates within one room type" => [ "101", "101" ],
    "quantity mismatches" => [ "101" ]
  }.each do |description, numbers|
    it "rejects #{description} before it inserts rooms" do
      room_type = create(:room_type, quantity: 2, room_numbers: [])
      room_type.update_column(:room_numbers, numbers)
      Room.where(hotel: room_type.hotel).delete_all

      expect { ActiveRecord::Migration.suppress_messages { migration.up } }
        .to raise_error(ActiveRecord::MigrationError, /hotel #{room_type.hotel_id}.*room type #{room_type.id}/m)
      expect(Room.where(hotel: room_type.hotel)).to be_empty
    end
  end

  it "allows the same room number in different hotels" do
    first = create(:room_type, quantity: 1, room_numbers: [ "101" ])
    second = create(:room_type, quantity: 1, room_numbers: [ "101" ])
    Room.where(hotel_id: [ first.hotel_id, second.hotel_id ]).delete_all

    ActiveRecord::Migration.suppress_messages { migration.up }

    expect(Room.where(number: "101", hotel_id: [ first.hotel_id, second.hotel_id ]).count).to eq(2)
  end
end
