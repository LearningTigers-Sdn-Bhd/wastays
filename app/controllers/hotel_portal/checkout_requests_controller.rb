# frozen_string_literal: true

module HotelPortal
  class CheckoutRequestsController < HotelPortal::BaseController
    include HousekeepingBoardFilters
    include HousekeepingTaskAuthorization

    before_action :authorize_manage_checkout_requests!
    before_action :set_checkout_request

    def complete
      request = ::CheckoutRequests::CompleteRequest.new(
        hotel: current_hotel,
        checkout_request: @checkout_request
      ).call

      if request
        respond_to do |format|
          format.html { redirect_to hotel_requests_path(current_hotel), notice: "Checkout sent to housekeeping." }
          format.json { render json: { ok: true, status: request.status } }
        end
      else
        respond_to do |format|
          format.html { redirect_to hotel_requests_path(current_hotel), alert: "Request cannot be completed." }
          format.json { render json: { ok: false }, status: :unprocessable_entity }
        end
      end
    end

    private

    def set_checkout_request
      @checkout_request = CheckOutRequest.joins(:booking)
                                         .where(bookings: { hotel_id: current_hotel.id })
                                         .find(params[:id])
    rescue TypeError, ActiveRecord::RecordNotFound
      respond_to do |format|
        format.html { redirect_to hotel_requests_path(current_hotel), alert: "Request not found." }
        format.json { render json: { ok: false }, status: :not_found }
      end
    end

    def authorize_manage_checkout_requests!
      allowed = current_user.has_permission?("manage_requests", hotel: current_hotel) ||
                current_user.has_permission?("perform_housekeeping_tasks", hotel: current_hotel) ||
                current_user.has_permission?("dispatch_housekeeping_tasks", hotel: current_hotel)
      raise Pundit::NotAuthorizedError unless allowed
    end
  end
end
