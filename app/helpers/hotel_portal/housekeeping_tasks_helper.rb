# frozen_string_literal: true

module HotelPortal
  module HousekeepingTasksHelper
    # Built from the one list of statuses the board can actually show, so a new
    # room status cannot be filterable on one page and invisible on another.
    def room_status_filter_options
      [ [ "All Room Statuses", "" ] ] +
        ::Rooms::StatusPresentation::RESOLVED_STATUSES.map { |status| [ ::Rooms::StatusPresentation.label(status), status ] }
    end
  end
end
