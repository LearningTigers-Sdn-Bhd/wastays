# frozen_string_literal: true

module HousekeepingTasks
  TaskRow = Struct.new(
    :id,
    :booking,
    :room_number,
    :request_details,
    :status,
    :metadata,
    :created_at,
    :requested_at,
    :source_kind,
    keyword_init: true
  ) do
    def checkout_request?
      source_kind == "checkout"
    end

    def assigned_to_id
      metadata.to_h["assigned_to"]
    end

    def assigned_to_name
      metadata.to_h["assigned_to_name"].presence || "Unassigned"
    end

    def display_status
      return status unless checkout_request?

      metadata.to_h["workflow_status"].presence ||
        HousekeepingTasks.checkout_workflow_status_for(status)
    end
  end

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
