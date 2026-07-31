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
    # A room with nothing to do still occupies a line on the board, and that line
    # is this row. It stands for the absence of a task rather than a task.
    def placeholder?
      status == "no_task"
    end

    def assigned_to_id
      metadata.to_h["assigned_to"]
    end

    def assigned_to_name
      metadata.to_h["assigned_to_name"].presence || "Unassigned"
    end

    def display_status
      status
    end
  end
end
