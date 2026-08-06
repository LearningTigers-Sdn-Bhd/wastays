# frozen_string_literal: true

require "rails_helper"

RSpec.describe HousekeepingTasks::AssignStaff do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account:) }

  # Two different rooms that happen to share the number 101.
  let(:penthouse) { create(:room_type, hotel:, room_number_mode: "custom", room_numbers: %w[101]) }
  let(:garden_suite) { create(:room_type, hotel:, room_number_mode: "custom", room_numbers: %w[101]) }

  # Only users on a "housekeeper" role are assignable, per ActiveHousekeepersQuery.
  let(:housekeeper_role) do
    create(:role, account:, slug: "housekeeper", name: "Housekeeper").tap do |role|
      grant(role, "perform_housekeeping_tasks")
    end
  end

  def grant(role, *slugs)
    slugs.each do |slug|
      permission = Permission.find_or_create_by!(slug:) { |record| record.name = slug.humanize }
      RolePermission.find_or_create_by!(role:, permission:)
    end
  end

  def housekeeper(name)
    create(:user, account:, name:).tap do |user|
      create(:user_hotel_access, user:, hotel:, role: housekeeper_role)
    end
  end

  def user_with(*slugs, name:)
    role = create(:role, account:, slug: "role-#{SecureRandom.hex(4)}", name: name)
    grant(role, *slugs)
    create(:user, account:, name:).tap do |user|
      create(:user_hotel_access, user:, hotel:, role:)
    end
  end

  def booking_on(room_type)
    create(:booking, hotel:).tap do |booking|
      create(:booking_room, booking:, room_type:, room_number: "101")
    end
  end

  def task_on(room_type, details:, assigned_to: nil)
    booking = booking_on(room_type)
    create(
      :housekeeping_request,
      booking:,
      hotel:,
      room_number: "101",
      status: assigned_to ? "assigned" : "in_progress",
      request_details: details,
      work_context: "vacant_room_task",
      metadata: assigned_to ? { "assigned_to" => assigned_to.id, "assigned_to_name" => assigned_to.name } : {}
    )
  end

  def assign(request, to:, as:)
    described_class.new(hotel:, request_id: request.id, assigned_to_id: to&.id, current_user: as).call
  end

  let(:dispatcher) { user_with("perform_housekeeping_tasks", "dispatch_housekeeping_tasks", name: "Dana Dispatch") }

  describe "room identity" do
    it "leaves the same room number in a different room type alone" do
      penthouse_task = task_on(penthouse, details: "Penthouse towels")
      garden_task = task_on(garden_suite, details: "Garden towels")
      sam = housekeeper("Sam Lee")

      assign(penthouse_task, to: sam, as: dispatcher)

      expect(penthouse_task.reload.metadata["assigned_to"]).to eq(sam.id)
      expect(garden_task.reload.metadata["assigned_to"]).to be_nil
    end

    it "still covers every task belonging to the one real room" do
      first = task_on(penthouse, details: "Penthouse towels")
      second = create(
        :housekeeping_request,
        booking: first.booking,
        hotel:,
        room_number: "101",
        status: "in_progress",
        request_details: "Penthouse minibar",
        work_context: "vacant_room_task"
      )
      sam = housekeeper("Sam Lee")

      assign(first, to: sam, as: dispatcher)

      expect(second.reload.metadata["assigned_to"]).to eq(sam.id)
    end
  end

  describe "who may assign whom" do
    it "lets a dispatcher hand work to somebody else" do
      task = task_on(penthouse, details: "Towels")
      sam = housekeeper("Sam Lee")

      assign(task, to: sam, as: dispatcher)

      expect(task.reload.metadata["assigned_to"]).to eq(sam.id)
    end

    it "lets a dispatcher move a task from one person to another" do
      alex = housekeeper("Alex Tan")
      task = task_on(penthouse, details: "Towels", assigned_to: alex)
      sam = housekeeper("Sam Lee")

      assign(task, to: sam, as: dispatcher)

      expect(task.reload.metadata["assigned_to"]).to eq(sam.id)
    end

    it "lets a performer take unassigned work for themselves" do
      task = task_on(penthouse, details: "Towels")
      sam = housekeeper("Sam Lee")

      assign(task, to: sam, as: sam)

      expect(task.reload.metadata["assigned_to"]).to eq(sam.id)
    end

    it "lets a performer release their own work" do
      sam = housekeeper("Sam Lee")
      task = task_on(penthouse, details: "Towels", assigned_to: sam)

      assign(task, to: nil, as: sam)

      expect(task.reload.metadata["assigned_to"]).to be_nil
    end

    it "refuses to let a performer hand work to a colleague" do
      task = task_on(penthouse, details: "Towels")
      alex = housekeeper("Alex Tan")
      sam = user_with("perform_housekeeping_tasks", name: "Sam Lee")

      expect { assign(task, to: alex, as: sam) }.to raise_error(Pundit::NotAuthorizedError)
      expect(task.reload.metadata["assigned_to"]).to be_nil
    end

    it "refuses to let a performer take work off a colleague" do
      alex = housekeeper("Alex Tan")
      task = task_on(penthouse, details: "Towels", assigned_to: alex)
      sam = housekeeper("Sam Lee")

      expect { assign(task, to: sam, as: sam) }.to raise_error(Pundit::NotAuthorizedError)
      expect(task.reload.metadata["assigned_to"]).to eq(alex.id)
    end

    it "refuses to let a performer release a colleague's work" do
      alex = housekeeper("Alex Tan")
      task = task_on(penthouse, details: "Towels", assigned_to: alex)
      sam = housekeeper("Sam Lee")

      expect { assign(task, to: nil, as: sam) }.to raise_error(Pundit::NotAuthorizedError)
      expect(task.reload.metadata["assigned_to"]).to eq(alex.id)
    end

    it "turns away a user holding neither half" do
      task = task_on(penthouse, details: "Towels")
      sam = housekeeper("Sam Lee")
      bystander = user_with("manage_requests", name: "Bystander")

      expect { assign(task, to: sam, as: bystander) }.to raise_error(Pundit::NotAuthorizedError)
      expect(task.reload.metadata["assigned_to"]).to be_nil
    end
  end

  describe "what assigning does to a housekeeping request" do
    %w[new no_task pending].each do |status|
      it "moves a #{status} task to assigned" do
        task = create(:housekeeping_request, booking: booking_on(penthouse), hotel:, room_number: "101", status:,
                      work_context: "vacant_room_task")
        sam = housekeeper("Sam Lee")

        assign(task, to: sam, as: dispatcher)

        expect(task.reload).to have_attributes(status: "assigned")
        expect(task.metadata).to include("assigned_to" => sam.id, "assigned_to_name" => "Sam Lee")
      end
    end

    it "leaves a task already under way under way" do
      task = task_on(penthouse, details: "Towels")
      sam = housekeeper("Sam Lee")

      assign(task, to: sam, as: dispatcher)

      expect(task.reload.status).to eq("in_progress")
    end

    it "puts a released task back to new, and takes the holder off it" do
      sam = housekeeper("Sam Lee")
      task = task_on(penthouse, details: "Towels", assigned_to: sam)

      assign(task, to: nil, as: dispatcher)

      expect(task.reload.status).to eq("new")
      expect(task.metadata).not_to include("assigned_to", "assigned_to_name")
    end

    it "leaves a released task that was under way under way" do
      sam = housekeeper("Sam Lee")
      task = task_on(penthouse, details: "Towels", assigned_to: sam)
      task.update!(status: "in_progress")

      assign(task, to: nil, as: dispatcher)

      expect(task.reload.status).to eq("in_progress")
    end

    it "keeps no workflow status of its own" do
      task = task_on(penthouse, details: "Towels")

      assign(task, to: housekeeper("Sam Lee"), as: dispatcher)

      expect(task.reload.metadata).not_to include("workflow_status")
    end
  end

  describe "one room, one assignment" do
    it "hands a room's turnover and housekeeping work to the same person at once" do
      housekeeping = task_on(penthouse, details: "Towels")
      turnover = create(:housekeeping_request, booking: housekeeping.booking, hotel:, room_type: penthouse,
                        room_number: "101", work_context: "checkout_turnover",
                        status: "new", request_details: "Checkout turnover")
      sam = housekeeper("Sam Lee")

      assign(housekeeping, to: sam, as: dispatcher)

      expect(housekeeping.reload.metadata["assigned_to"]).to eq(sam.id)
      expect(turnover.reload.metadata["assigned_to"]).to eq(sam.id)
    end

    it "leaves a placeholder record alone while the room has real work" do
      real = task_on(penthouse, details: "Towels")
      placeholder = create(:housekeeping_request, booking: real.booking, hotel:, room_number: "101",
                           status: "no_task", request_details: "-", work_context: "vacant_room_task")
      sam = housekeeper("Sam Lee")

      assign(real, to: sam, as: dispatcher)

      expect(real.reload.metadata["assigned_to"]).to eq(sam.id)
      expect(placeholder.reload.metadata["assigned_to"]).to be_nil
      expect(placeholder.status).to eq("no_task")
    end

    it "takes the placeholder itself when that is all the room has" do
      placeholder = create(:housekeeping_request, booking: booking_on(penthouse), hotel:, room_number: "101",
                           status: "no_task", request_details: "-", work_context: "vacant_room_task")
      sam = housekeeper("Sam Lee")

      assign(placeholder, to: sam, as: dispatcher)

      expect(placeholder.reload).to have_attributes(status: "assigned")
      expect(placeholder.metadata["assigned_to"]).to eq(sam.id)
    end
  end

  describe "the trail it leaves" do
    it "records who was assigned, by whom, on each task of the room" do
      task = task_on(penthouse, details: "Towels")
      sam = housekeeper("Sam Lee")

      assign(task, to: sam, as: dispatcher)

      entry = task.reload.metadata["assignment_history"].last
      expect(entry).to include(
        "assigned_to_id" => sam.id, "assigned_to_name" => "Sam Lee",
        "assigned_by_id" => dispatcher.id, "assigned_by_name" => "Dana Dispatch"
      )
      expect(entry["timestamp"]).to be_present
    end

    it "records a release without naming anybody as the new holder" do
      sam = housekeeper("Sam Lee")
      task = task_on(penthouse, details: "Towels", assigned_to: sam)

      assign(task, to: nil, as: dispatcher)

      entry = task.reload.metadata["assignment_history"].last
      expect(entry["assigned_to_name"]).to eq("Unassigned")
      expect(entry).not_to include("assigned_to_id")
    end

    it "writes one audit event naming every task it moved" do
      housekeeping = task_on(penthouse, details: "Towels")
      turnover = create(:housekeeping_request, booking: housekeeping.booking, hotel:, room_type: penthouse,
                        room_number: "101", work_context: "checkout_turnover",
                        status: "new", request_details: "Checkout turnover")
      sam = housekeeper("Sam Lee")

      assign(housekeeping, to: sam, as: dispatcher)

      audit = RoomOperationalAuditLog.where(hotel:, event_type: "housekeeping_assignment_changed").sole
      expect(audit).to have_attributes(room_number: "101", user: dispatcher, room_type: penthouse)
      expect(audit.reason).to eq("Assigned room cleaning tasks to Sam Lee")
      expect(audit.metadata["tasks"]).to contain_exactly(
        { "type" => "HousekeepingRequest", "id" => housekeeping.id },
        { "type" => "HousekeepingRequest", "id" => turnover.id }
      )
    end

    it "says so when the work was handed back rather than out" do
      sam = housekeeper("Sam Lee")
      task = task_on(penthouse, details: "Towels", assigned_to: sam)

      assign(task, to: nil, as: dispatcher)

      expect(RoomOperationalAuditLog.sole.reason).to eq("Unassigned room cleaning tasks")
    end

    it "stays quiet when the holder did not actually change" do
      sam = housekeeper("Sam Lee")
      task = task_on(penthouse, details: "Towels", assigned_to: sam)

      assign(task, to: sam, as: dispatcher)

      expect(RoomOperationalAuditLog.count).to eq(0)
      expect(task.reload.metadata["assignment_history"]).to be_blank
    end
  end
end
