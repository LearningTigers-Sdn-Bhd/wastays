module Public
  module Concierge
    class RequestsController < BaseController
      def new
        @booking = request_lookup_stage? ? current_concierge_booking : nil
      end

      def create
        booking = resolve_booking_from_params
        return unless booking

        if params[:stage] != "submit"
          return render_request_lookup_error(booking) unless booking.status.in?(%w[confirmed checked_in])

          set_concierge_booking_cookie(booking)
          return redirect_to concierge_new_request_path(@hotel.slug, stage: "submit")
        end

        result = ::Concierge::SubmitGuestRequest.new(
          booking: booking,
          kind: params[:kind],
          details: params[:details]
        ).call

        if result.success?
          set_concierge_booking_cookie(booking)
          flash[:concierge_request_kind] = params[:kind].to_s
          flash[:concierge_request_details] = params[:details].to_s.strip
          redirect_to concierge_request_success_path(@hotel.slug)
        else
          @error = result.message
          @booking = booking
          render :new, status: :unprocessable_content
        end
      end

      def success
        @booking = current_concierge_booking
        redirect_to concierge_home_path(@hotel.slug) unless @booking
      end

      private

      def resolve_booking_from_params
        resolve_concierge_booking_from_params(
          not_found_message: "Booking not found.",
          fallback_message: "Something went wrong."
        )
      end

      def request_lookup_stage?
        params[:stage] == "submit"
      end

      def render_request_lookup_error(booking)
        @booking = nil
        @error = if booking.status == "completed"
          "This booking has already been checked out."
        elsif booking.status == "cancelled"
          "This booking has been cancelled."
        else
          "Requests can only be submitted for active bookings."
        end
        render :new, status: :unprocessable_content
      end
    end
  end
end
