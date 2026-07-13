# frozen_string_literal: true

module HousekeepingTasks
  def self.checkout_workflow_status_for(status)
    case status.to_s
    when "pending" then "new"
    when "acknowledged" then "assigned"
    when "completed" then "completed"
    when "cancelled" then "no_task"
    else "new"
    end
  end
end
