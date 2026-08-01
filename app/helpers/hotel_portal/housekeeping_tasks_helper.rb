# frozen_string_literal: true

module HotelPortal
  module HousekeepingTasksHelper
    def booking_status_filter_options
      [ [ "All booking statuses", "" ] ] +
        ::HousekeepingTasks::BoardBuilder::BOOKING_STATUSES.map { |value, label| [ label, value ] }
    end
  end
end
