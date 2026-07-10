module HotelPortal
  class CheckoutRequestsController < HotelPortal::BaseController
    before_action :authorize_manage_checkout_requests!
    before_action :set_checkout_request

    def assign
      assigned_to = params[:assigned_to].presence
      metadata = @checkout_request.metadata.to_h
      staff = nil

      if assigned_to.present?
        staff = User.where(id: UserHotelAccess.active
                                               .where(hotel_id: current_hotel.id)
                                               .joins(:role)
                                               .where(roles: { slug: "housekeeper" })
                                               .select(:user_id))
                    .find_by(id: assigned_to)
      end

      if staff
        if metadata["assigned_to"] != staff.id
          history = Array(metadata["assignment_history"])
          history << {
            "assigned_to_id" => staff.id,
            "assigned_to_name" => staff.name,
            "assigned_by_id" => current_user.id,
            "assigned_by_name" => current_user.name,
            "timestamp" => Time.current.iso8601
          }
          metadata["assignment_history"] = history
        end
        metadata["assigned_to"] = staff.id
        metadata["assigned_to_name"] = staff.name
        metadata["workflow_status"] = "assigned"
        @checkout_request.status = "assigned" if @checkout_request.status.in?(%w[new pending acknowledged])
      else
        if metadata["assigned_to"].present?
          history = Array(metadata["assignment_history"])
          history << {
            "assigned_to_name" => "Unassigned",
            "assigned_by_id" => current_user.id,
            "assigned_by_name" => current_user.name,
            "timestamp" => Time.current.iso8601
          }
          metadata["assignment_history"] = history
        end
        metadata.delete("assigned_to")
        metadata.delete("assigned_to_name")
        metadata["workflow_status"] = "new"
        @checkout_request.status = "new" if @checkout_request.status.in?(%w[assigned in_progress acknowledged])
      end

      @checkout_request.update!(metadata: metadata)

      respond_to do |format|
        format.html { redirect_to hotel_housekeeping_tasks_path(current_hotel), notice: "Checkout request assigned successfully." }
        format.json { render json: { ok: true, status: @checkout_request.status } }
      end
    end

    def complete
      if @checkout_request.status.in?(%w[new assigned in_progress pending acknowledged])
        request = ::HotelPortal::Requests::StatusUpdater.new(
          hotel: current_hotel,
          kind: :checkout,
          request_id: @checkout_request.id,
          status: "completed"
        ).call
        return redirect_to(hotel_requests_path(current_hotel), alert: "Request could not be completed.") unless request

        booking = @checkout_request.booking
        ::Bookings::TransitionStatus.new(booking: booking, status: "completed").call if booking.checked_in?
        # Booking checkout marks assigned rooms dirty; restore the cleaning result.
        ::HotelPortal::Requests::StatusUpdater.new(
          hotel: current_hotel,
          kind: :checkout,
          request_id: @checkout_request.id,
          status: "completed"
        ).call
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

    def authorize_manage_checkout_requests!
      allowed = current_user.has_permission?("manage_requests", hotel: current_hotel) ||
                current_user.has_permission?("manage_housekeeping_tasks", hotel: current_hotel)
      raise Pundit::NotAuthorizedError unless allowed
    end
  end
end
