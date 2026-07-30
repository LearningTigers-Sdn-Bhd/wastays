# frozen_string_literal: true

require "rails_helper"

RSpec.describe HousekeepingTasks::TaskRow do
  def row(status: "assigned", source_kind: "housekeeping", metadata: {})
    described_class.new(
      id: 1, booking: nil, room_number: "101", request_details: "Fresh towels",
      status: status, metadata: metadata, created_at: Time.current,
      requested_at: Time.current, source_kind: source_kind
    )
  end

  describe "which kind of task it stands for" do
    it "knows a checkout cleaning from ordinary housekeeping work" do
      expect(row(source_kind: "checkout")).to be_checkout_request
      expect(row).not_to be_checkout_request
    end
  end

  describe "standing in for no work at all" do
    it "is a placeholder when that is all it says" do
      expect(row(status: "no_task")).to be_placeholder
      expect(row(status: "new")).not_to be_placeholder
    end
  end

  describe "who holds it" do
    it "reads the holder out of the metadata" do
      expect(row(metadata: { "assigned_to" => 7, "assigned_to_name" => "Sam Lee" })).to have_attributes(
        assigned_to_id: 7, assigned_to_name: "Sam Lee"
      )
    end

    it "says so plainly when nobody does" do
      expect(row.assigned_to_id).to be_nil
      expect(row.assigned_to_name).to eq("Unassigned")
    end
  end

  describe "the status the board shows" do
    it "is a housekeeping task's own status" do
      expect(row(status: "in_progress").display_status).to eq("in_progress")
    end

    it "is a checkout request's workflow status, which it keeps in metadata" do
      task = row(status: "pending", source_kind: "checkout", metadata: { "workflow_status" => "in_progress" })

      expect(task.display_status).to eq("in_progress")
    end

    # A request raised before workflow_status existed has none to read, so its
    # own status is translated instead.
    it "falls back to reading a checkout request's own status" do
      expect(row(status: "pending", source_kind: "checkout").display_status).to eq("new")
      expect(row(status: "acknowledged", source_kind: "checkout").display_status).to eq("assigned")
    end
  end
end
