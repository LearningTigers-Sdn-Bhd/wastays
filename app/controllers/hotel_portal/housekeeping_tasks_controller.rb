# frozen_string_literal: true

module HotelPortal
  class HousekeepingTasksController < BaseController
    before_action :authorize_manage_requests!
    before_action -> { require_feature!("task_assignment_minibar_log") }

    def index
      # We query housekeeping requests belonging to the hotel's bookings.
      @base_scope = HousekeepingRequest.joins(:booking).where(bookings: { hotel_id: current_hotel.id })

      # Only active (unarchived) housekeeping requests
      @housekeeping_requests = @base_scope.active

      # Filter by status
      if params[:status].present? && params[:status] != "all"
        @housekeeping_requests = @housekeeping_requests.where(status: params[:status])
      end

      # Filter by room number
      if params[:room_number].present?
        @housekeeping_requests = @housekeeping_requests.where(room_number: params[:room_number])
      end

      # Search query
      if params[:q].present?
        @housekeeping_requests = @housekeeping_requests.search(params[:q])
      end

      @housekeeping_requests = @housekeeping_requests.recent_first.page(params[:page]).per(25)
    end

    private

    def authorize_manage_requests!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_requests", hotel: current_hotel)
    end
  end
end
