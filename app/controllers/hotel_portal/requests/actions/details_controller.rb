# frozen_string_literal: true

module HotelPortal
  module Requests
    module Actions
      # One request's detail, as a sheet on the requests board and its archive.
      #
      # Read-only, like Bookings::Actions::AuditTrailsController: the board's own
      # buttons still advance and archive work. What this replaces is a dialog
      # rendered once per card, which put a hundred of them in a page to show one.
      class DetailsController < HotelPortal::BaseController
        include RequestActionCompletion

        before_action :authorize_manage_requests!
        before_action -> { require_feature!("task_assignment_minibar_log") }
        before_action :set_request
        before_action :set_return_to

        rescue_from ActiveRecord::RecordNotFound, with: :handle_record_not_found

        def show
          render :show, layout: false
        end

        private

        def set_request
          record = ::HotelPortal::Requests::Finder.new(
            hotel: current_hotel,
            kind: params[:kind],
            request_id: params[:request_id]
          ).call

          @presenter = ::HotelPortal::Requests::DetailPresenter.new(
            request: record,
            kind: params[:kind],
            hotel: current_hotel
          )
        end

        def set_return_to
          @return_to = request_action_return_to(fallback: hotel_requests_path(current_hotel))
        end

        def authorize_manage_requests!
          raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_requests", hotel: current_hotel)
        end

        def handle_record_not_found
          respond_to do |format|
            format.html { redirect_to hotel_requests_path(current_hotel), alert: "Request not found." }
            format.any { head :not_found }
          end
        end
      end
    end
  end
end
