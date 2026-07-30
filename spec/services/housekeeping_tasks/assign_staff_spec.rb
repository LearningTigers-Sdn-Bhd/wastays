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

  def task_on(room_type, details:, assigned_to: nil)
    booking = create(:booking, hotel:)
    create(:booking_room, booking:, room_type:, room_number: "101")
    create(
      :housekeeping_request,
      booking:,
      hotel:,
      room_number: "101",
      status: assigned_to ? "assigned" : "in_progress",
      request_details: details,
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
        request_details: "Penthouse minibar"
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
end
