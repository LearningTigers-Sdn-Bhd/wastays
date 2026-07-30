# frozen_string_literal: true

require "rails_helper"

RSpec.describe HousekeepingTasks do
  describe ".checkout_workflow_status_for" do
    # A CheckOutRequest predates the workflow the board speaks, so its own
    # statuses have to be read as workflow statuses.
    {
      "pending" => "new",
      "acknowledged" => "assigned",
      "completed" => "completed",
      "cancelled" => "no_task"
    }.each do |own_status, workflow_status|
      it "reads #{own_status} as #{workflow_status}" do
        expect(described_class.checkout_workflow_status_for(own_status)).to eq(workflow_status)
      end
    end

    # Worth knowing: a status the board already speaks is not passed through.
    # It only matters for a request written before workflow_status existed --
    # anything assigned since carries its own, and TaskRow reads that first.
    it "does not pass through a status the board already speaks" do
      expect(described_class.checkout_workflow_status_for("assigned")).to eq("new")
      expect(described_class.checkout_workflow_status_for("in_progress")).to eq("new")
    end

    it "treats anything it cannot place as work not started" do
      expect(described_class.checkout_workflow_status_for(nil)).to eq("new")
      expect(described_class.checkout_workflow_status_for("something_else")).to eq("new")
    end
  end
end
