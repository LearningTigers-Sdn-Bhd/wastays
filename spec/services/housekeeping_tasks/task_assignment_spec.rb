# frozen_string_literal: true

require "rails_helper"

RSpec.describe HousekeepingTasks::TaskAssignment do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account:) }
  let(:room_type) { create(:room_type, hotel:, room_number_mode: "custom", room_numbers: %w[101]) }
  let(:booking) do
    create(:booking, hotel:).tap { |record| create(:booking_room, booking: record, room_type:, room_number: "101") }
  end
  let(:dispatcher) { create(:user, account:, name: "Dana Dispatch") }
  let(:sam) { create(:user, account:, name: "Sam Lee") }

  def housekeeping_task(status: "new", metadata: {})
    create(:housekeeping_request, booking:, hotel:, room_number: "101", status:, metadata:,
           work_context: "vacant_room_task")
  end

  describe "standing in for no work" do
    it "is a placeholder only where a status can say so" do
      expect(described_class.new(housekeeping_task(status: "no_task"))).to be_placeholder
      expect(described_class.new(housekeeping_task(status: "new"))).not_to be_placeholder
    end
  end

  describe "who holds the task" do
    it "reads the holder, and whether it is somebody other than this user" do
      assignment = described_class.new(housekeeping_task(metadata: { "assigned_to" => sam.id }))

      expect(assignment.assigned_to).to eq(sam.id)
      expect(assignment).to be_held_by_somebody_else(dispatcher)
      expect(assignment).not_to be_held_by_somebody_else(sam)
    end

    it "counts unheld work as nobody else's" do
      expect(described_class.new(housekeeping_task)).not_to be_held_by_somebody_else(dispatcher)
    end
  end

  describe "handing a housekeeping task over" do
    it "moves it to assigned and names the holder" do
      task = housekeeping_task
      changed = described_class.new(task).hand_over(sam, by: dispatcher)

      expect(changed).to be(true)
      expect(task.reload.status).to eq("assigned")
      expect(task.metadata).to include("assigned_to" => sam.id, "assigned_to_name" => "Sam Lee")
      expect(task.metadata).not_to include("workflow_status")
    end

    it "hands it back to nobody, putting it to new" do
      task = housekeeping_task(status: "assigned", metadata: { "assigned_to" => sam.id, "assigned_to_name" => "Sam Lee" })
      changed = described_class.new(task).hand_over(nil, by: dispatcher)

      expect(changed).to be(true)
      expect(task.reload.status).to eq("new")
      expect(task.metadata).not_to include("assigned_to")
    end

    it "reports no change when the same person holds it already" do
      task = housekeeping_task(status: "assigned", metadata: { "assigned_to" => sam.id, "assigned_to_name" => "Sam Lee" })

      expect(described_class.new(task).hand_over(sam, by: dispatcher)).to be(false)
      expect(task.reload.metadata["assignment_history"]).to be_blank
    end
  end

  describe "the trail it writes" do
    it "notes who was given the task, and by whom" do
      task = housekeeping_task
      described_class.new(task).hand_over(sam, by: dispatcher)

      expect(task.reload.metadata["assignment_history"].last).to include(
        "assigned_to_id" => sam.id, "assigned_to_name" => "Sam Lee",
        "assigned_by_id" => dispatcher.id, "assigned_by_name" => "Dana Dispatch"
      )
    end

    it "notes a release without naming a new holder" do
      task = housekeeping_task(status: "assigned", metadata: { "assigned_to" => sam.id })
      described_class.new(task).hand_over(nil, by: dispatcher)

      entry = task.reload.metadata["assignment_history"].last
      expect(entry["assigned_to_name"]).to eq("Unassigned")
      expect(entry).not_to include("assigned_to_id")
    end
  end

  describe "naming itself for the audit log" do
    it "reports its own kind and id" do
      task = housekeeping_task

      expect(described_class.new(task).audit_entry).to eq("type" => "HousekeepingRequest", "id" => task.id)
    end
  end

  # Who holds a record is written in its metadata whatever kind it is, and the
  # Requests board asks that of a checkout. Handing one out is what this board
  # has no rules for, and that is what refuses.
  it "answers who holds a record it cannot hand out" do
    checkout = create(:check_out_request, metadata: { "assigned_to" => 42 })

    expect(described_class.new(checkout).assigned_to).to eq(42)
  end

  it "refuses to hand out a record it has no rules for" do
    checkout = create(:check_out_request)

    expect { described_class.new(checkout).hand_over(nil, by: dispatcher) }.to raise_error(KeyError)
  end
end
