# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260801100000_move_housekeeping_operations_to_room_statuses")

RSpec.describe MoveHousekeepingOperationsToRoomStatuses do
  subject(:migration) { described_class.new }

  around do |example|
    if ActiveRecord::Base.connection.column_exists?(:room_statuses, :assigned_to_id)
      ActiveRecord::Migration.suppress_messages { migration.down }
      RoomStatus.reset_column_information
    end

    example.run
  ensure
    unless ActiveRecord::Base.connection.column_exists?(:room_statuses, :assigned_to_id)
      ActiveRecord::Migration.suppress_messages { migration.up }
      RoomStatus.reset_column_information
    end
  end

  it "backfills current room operations and archives legacy operational tasks" do
    hotel = create(:hotel)
    room_type = create(:room_type, hotel:, room_number_mode: "custom", quantity: 2, room_numbers: %w[101 202])
    existing = create(:room_status, hotel:, room_type:, room_number: "101", status: "cleaning", notes: nil)
    booking = create(:booking, hotel:)
    create(:booking_room, booking:, room_type:, room_number: "101")

    housekeeper_role = create(:role, account: hotel.account, slug: "housekeeper", name: "Housekeeper")
    housekeeper = create(:user, account: hotel.account)
    create(:user_hotel_access, user: housekeeper, hotel:, role: housekeeper_role)

    older = create(
      :housekeeping_request,
      booking:,
      hotel:,
      room_type:,
      room_number: "101",
      work_context: "vacant_room_task",
      status: "new",
      request_details: "Older note",
      requested_at: 2.hours.ago
    )
    latest = create(
      :housekeeping_request,
      booking:,
      hotel:,
      room_type:,
      room_number: "101",
      work_context: "vacant_room_task",
      status: "assigned",
      request_details: "Bring fresh linen",
      requested_at: 1.hour.ago,
      metadata: { "assigned_to" => housekeeper.id }
    )
    new_room_task = create(
      :housekeeping_request,
      hotel:,
      room_type:,
      room_number: "202",
      work_context: "checkout_turnover",
      status: "new",
      request_details: "Checkout turnover"
    )

    ActiveRecord::Migration.suppress_messages { migration.up }
    RoomStatus.reset_column_information

    expect(existing.reload).to have_attributes(
      status: "cleaning",
      notes: "Bring fresh linen",
      assigned_to_id: housekeeper.id
    )
    expect(RoomStatus.find_by!(hotel:, room_type:, room_number: "202")).to have_attributes(
      status: "dirty",
      notes: "Checkout turnover"
    )
    expect([ older, latest, new_room_task ].map { |task| task.reload.archived_at }).to all(be_present)
  end
end
