# frozen_string_literal: true

# The housekeeping board and everything that hands work out on it. Not
# ActiveRecord: TaskRow is a row on the board rather than a row in a table, and
# a checkout request's own statuses predate the workflow the board speaks.
module HousekeepingTasks
  # A CheckOutRequest carries legacy statuses of its own. Read one as the
  # workflow status the board works in, for requests written before the
  # workflow_status metadata existed.
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
