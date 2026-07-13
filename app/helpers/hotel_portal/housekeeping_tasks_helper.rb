# frozen_string_literal: true

module HotelPortal
  module HousekeepingTasksHelper
    ROOM_STATUS_OPTIONS = [
      [ "All Room Statuses", "" ],
      [ "Ready", "ready" ],
      [ "Dirty", "dirty" ],
      [ "Cleaning", "cleaning" ],
      [ "Occupied", "occupied" ],
      [ "Awaiting Inspection", "awaiting_inspection" ],
      [ "Inspection Failed", "inspection_failed" ],
      [ "Out of Service", "out_of_service" ],
      [ "Late Checkout Detected", "late_checkout_detected" ]
    ].freeze

    TASK_STATUS_OPTIONS = [
      [ "No Task", "no_task" ],
      [ "New", "new" ],
      [ "Assigned", "assigned" ],
      [ "In Progress", "in_progress" ],
      [ "Completed", "completed" ]
    ].freeze

    def room_status_filter_options
      ROOM_STATUS_OPTIONS
    end

    def task_status_options
      TASK_STATUS_OPTIONS
    end
  end
end
