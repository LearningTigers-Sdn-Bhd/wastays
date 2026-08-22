module Public
  module Concierge
    class CheckOutsController < BaseController
      def new
        @booking = checkout_lookup_stage? ? current_concierge_booking : nil
        render "new_mobile" if mobile_request?
      end

      def create
        booking = resolve_booking_from_params
        return unless booking

        if params[:stage] != "submit"
          return render_checkout_lookup_error(booking) unless booking.checked_in?

          set_concierge_booking_cookie(booking)
          return redirect_to concierge_check_out_path(@hotel, stage: "submit")
        end

        result = ::Concierge::SubmitCheckOutRequest.new(
          booking: booking,
          guest_notes: params[:guest_notes]
        ).call

        if result.success?
          set_concierge_booking_cookie(booking)
          redirect_to concierge_check_out_success_path(@hotel)
        else
          @error = result.message
          @booking = booking
          render(mobile_request? ? "new_mobile" : :new, status: :unprocessable_content)
        end
      end

      def success
        @booking = current_concierge_booking
        redirect_to concierge_home_path(@hotel) unless @booking
      end

      private

      def resolve_booking_from_params
        resolve_concierge_booking_from_params(
          not_found_message: "Booking not found.",
          fallback_message: "Something went wrong."
        )
      end

      def checkout_lookup_stage?
        params[:stage] == "submit"
      end

      def render_checkout_lookup_error(booking)
        @booking = nil
        @error = if booking.status == "completed"
          "This booking has already been checked out."
        elsif booking.status == "cancelled"
          "This booking has been cancelled."
        else
          "Checkout can only be requested for checked-in bookings."
        end
        render(mobile_request? ? "new_mobile" : :new, status: :unprocessable_content)
      end
    end
  end
end
