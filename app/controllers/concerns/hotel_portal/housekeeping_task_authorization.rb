# frozen_string_literal: true

module HotelPortal
  # Who may move a housekeeping task along.
  #
  # Dispatching is handing work out; performing is doing it. A dispatcher runs
  # the floor, so they may advance anybody's task. A performer may advance the
  # work they hold and nothing else -- the same line HousekeepingTasks::AssignStaff
  # draws around taking and releasing, drawn again around starting and completing.
  module HousekeepingTaskAuthorization
    extend ActiveSupport::Concern

    included do
      helper_method :dispatch_housekeeping?
    end

    private

    def dispatch_housekeeping?
      return @dispatch_housekeeping if defined?(@dispatch_housekeeping)

      @dispatch_housekeeping = current_user.has_permission?("dispatch_housekeeping_tasks", hotel: current_hotel)
    end

    def authorize_advance!(record)
      return if dispatch_housekeeping?

      assignment = ::HousekeepingTasks::TaskAssignment.new(record)
      raise Pundit::NotAuthorizedError if assignment.held_by_somebody_else?(current_user)
    end
  end
end
