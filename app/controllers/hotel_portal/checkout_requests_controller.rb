# frozen_string_literal: true

module HotelPortal
  class CheckoutRequestsController < HotelPortal::BaseController
    before_action :authorize_manage_checkout_requests!
    before_action :set_checkout_request

    def assign
      ::CheckoutRequests::AssignStaff.new(
        hotel: current_hotel,
        checkout_request: @checkout_request,
        assigned_to_id: params[:assigned_to],
        current_user: current_user
      ).call

      respond_to do |format|
        format.html { redirect_to hotel_housekeeping_tasks_path(current_hotel), notice: "Checkout request assigned successfully." }
        format.json { render json: { ok: true, status: @checkout_request.status } }
      end
    end

    def complete
      request = ::CheckoutRequests::CompleteRequest.new(
        hotel: current_hotel,
        checkout_request: @checkout_request
      ).call

      if request
        respond_to do |format|
          format.html { redirect_to hotel_requests_path(current_hotel), notice: "Checkout completed." }
          format.json { render json: { ok: true, status: request.status } }
        end
      else
        respond_to do |format|
          format.html { redirect_to hotel_requests_path(current_hotel), alert: "Request cannot be completed." }
          format.json { render json: { ok: false }, status: :unprocessable_entity }
        end
      end
    end

    def update_status
      updater = ::HotelPortal::Requests::StatusUpdater.new(
        hotel: current_hotel,
        kind: :checkout,
        request_id: @checkout_request.id,
        status: params[:status]
      )

      redirect_target = params[:redirect_to].presence || hotel_housekeeping_tasks_path(current_hotel)
      if (request = updater.call)
        respond_to do |format|
          format.html { redirect_to redirect_target, notice: "Checkout request updated successfully." }
          format.json { render json: { ok: true, status: request.status } }
        end
      else
        respond_to do |format|
          format.html { redirect_to redirect_target, alert: "Failed to update checkout request." }
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
