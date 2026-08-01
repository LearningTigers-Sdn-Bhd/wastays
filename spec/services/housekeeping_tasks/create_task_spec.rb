# frozen_string_literal: true

require "rails_helper"

RSpec.describe HousekeepingTasks::CreateTask, frozen_time: Time.zone.local(2026, 8, 15, 12) do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account:) }
  let(:room_type) { create(:room_type, hotel:, name: "Ocean Suite", room_number_mode: "custom", room_numbers: %w[101]) }
  let(:dispatcher) { user_with("dispatch_housekeeping_tasks", "perform_housekeeping_tasks", name: "Dana Dispatch") }

  def user_with(*slugs, name:)
    role = create(:role, account:, slug: "role-#{SecureRandom.hex(4)}", name: name)
    slugs.each do |slug|
      permission = Permission.find_or_create_by!(slug:) { |record| record.name = slug.humanize }
      RolePermission.create!(role:, permission:)
    end
    create(:user, account:, name:).tap { |user| create(:user_hotel_access, user:, hotel:, role:) }
  end

  def housekeeper(name)
    hk_role = Role.find_or_create_by!(account:, slug: "housekeeper") { |record| record.name = "Housekeeper" }
    permission = Permission.find_or_create_by!(slug: "perform_housekeeping_tasks") { |record| record.name = "Perform" }
    RolePermission.find_or_create_by!(role: hk_role, permission:)
    create(:user, account:, name:).tap { |user| create(:user_hotel_access, user:, hotel:, role: hk_role) }
  end

  def dirty_room
    create(:room_status, hotel:, room_type:, room_number: "101", status: "dirty")
  end

  def add(details: "Full clean", assigned_to_id: nil)
    described_class.new(
      hotel:, room_type:, room_number: "101",
      details:, assigned_to_id:, current_user: dispatcher
    ).call
  end

  it "adds the task to the room rather than to whoever last stayed in it" do
    dirty_room
    departed = create(:booking, hotel:, status: "completed")
    create(:booking_room, booking: departed, room_type:, room_number: "101")

    result = add

    expect(result).to be_success
    expect(result.task).to have_attributes(
      hotel_id: hotel.id, room_type_id: room_type.id, room_number: "101",
      booking_id: nil, status: "new", request_details: "Full clean"
    )
  end

  it "asks for the work as of now, so the board looking at today can see it" do
    dirty_room

    expect(add.task.requested_at).to be_within(5.seconds).of(Time.current)
  end

  it "records who added it" do
    dirty_room

    expect(add.task.metadata).to include(
      "source" => "housekeeping_board",
      "created_by_id" => dispatcher.id,
      "created_by_name" => "Dana Dispatch"
    )
  end

  it "leaves the task for the floor when nobody was named" do
    dirty_room

    expect(add.task.metadata).not_to include("assigned_to")
    expect(add.task.status).to eq("new")
  end

  it "hands it over through AssignStaff when somebody was named" do
    dirty_room
    sam = housekeeper("Sam Lee")

    task = add(assigned_to_id: sam.id).task

    expect(task.status).to eq("assigned")
    expect(task.metadata).to include("assigned_to" => sam.id, "assigned_to_name" => "Sam Lee")
    expect(task.metadata["assignment_history"].last).to include("assigned_by_name" => "Dana Dispatch")
  end

  it "refuses unnamed work" do
    dirty_room

    result = add(details: "   ")

    expect(result).not_to be_success
    expect(result.error).to eq("Enter what needs doing.")
    expect(HousekeepingRequest.count).to eq(0)
  end

  it "refuses a room that is not waiting for a task" do
    create(:room_status, hotel:, room_type:, room_number: "101", status: "cleaning")

    result = add

    expect(result).not_to be_success
    expect(result.error).to include("not waiting for a task")
    expect(HousekeepingRequest.count).to eq(0)
  end

  it "refuses an occupied room nobody has marked dirty, which needs nothing yet" do
    booking = create(:booking, hotel:, status: "checked_in", check_in: Date.current, check_out: Date.tomorrow)
    create(:booking_room, booking:, room_type:, room_number: "101")

    expect(add).not_to be_success
  end

  it "refuses a dirty room with a guest still in it" do
    dirty_room
    booking = create(:booking, hotel:, status: "checked_in", check_in: Date.current, check_out: Date.tomorrow)
    create(:booking_room, booking:, room_type:, room_number: "101")

    expect(add).not_to be_success
  end

  it "adds nothing at all when the assignment is refused" do
    dirty_room

    expect { add(assigned_to_id: -1) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(HousekeepingRequest.count).to eq(0)
  end
end
