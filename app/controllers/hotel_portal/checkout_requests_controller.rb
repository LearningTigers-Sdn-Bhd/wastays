module HotelPortal
  class CheckoutRequestsController < HotelPortal::BaseController
    before_action :authorize_manage_requests!
    before_action :set_checkout_request

    def complete
      if @checkout_request.status.in?(%w[pending acknowledged])
        @checkout_request.update!(status: "completed")
        booking = @checkout_request.booking
        ::Bookings::TransitionStatus.new(booking: booking, status: "completed").call if booking.checked_in?
        respond_to do |format|
          format.html { redirect_to hotel_requests_path(current_hotel), notice: "Checkout completed." }
          format.json { render json: { ok: true, status: @checkout_request.status } }
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
      @checkout_request = current_hotel.bookings
                                       .joins(:check_out_requests)
                                       .where(check_out_requests: { id: params[:id] })
                                       .pick("check_out_requests.id")
                                       .then { |id| CheckOutRequest.find(id) }
    rescue TypeError, ActiveRecord::RecordNotFound
      respond_to do |format|
        format.html { redirect_to hotel_requests_path(current_hotel), alert: "Request not found." }
        format.json { render json: { ok: false }, status: :not_found }
      end
    end

    def authorize_manage_requests!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_requests", hotel: current_hotel)
    end
  end
end
