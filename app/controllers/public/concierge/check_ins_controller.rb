module Public
  module Concierge
    class CheckInsController < BaseController
      before_action :load_booking_from_cookie, only: [ :check_in_now, :submit_check_in, :check_in_success ]

      def new; end

      def lookup
        booking = resolve_concierge_booking_from_params(
          not_found_message: "Booking not found. Please check your confirmation code.",
          fallback_message: "Something went wrong. Please try again."
        )
        return unless booking

        case booking.status
        when "checked_in"
          redirect_to concierge_check_in_success_path(@hotel.slug)
        when "completed"
          @error = "This booking has already been checked out."
          render :new, status: :unprocessable_content
        when "cancelled"
          @error = "This booking has been cancelled."
          render :new, status: :unprocessable_content
        when "confirmed"
          if booking.pre_checkin&.completed?
            redirect_to concierge_check_in_now_path(@hotel.slug)
          else
            booking.create_pre_checkin!(
              status: "pending", document_status: "pending", signature_status: "pending"
            ) unless booking.pre_checkin.present?
            redirect_to pre_checkin_path(booking.pre_checkin.token)
          end
        else
          @error = "This booking is not ready for check-in. Please see the front desk."
          render :new, status: :unprocessable_content
        end
      end

      def check_in_now
        redirect_to concierge_check_in_path(@hotel.slug) unless @booking
      end

      def submit_check_in
        return redirect_to concierge_check_in_path(@hotel.slug) unless @booking

        result = ::Concierge::SelfCheckIn.new(booking: @booking).call

        if result.success?
          session[:concierge_check_in_room] = result.room_number
          redirect_to concierge_check_in_success_path(@hotel.slug)
        else
          @error_code = result.error_code
          render :check_in_now, status: :unprocessable_content
        end
      end

      def check_in_success
        @room_number = session.delete(:concierge_check_in_room) ||
                       @booking&.booking_rooms&.first&.room_number
        redirect_to concierge_home_path(@hotel.slug) unless @booking
      end

      private

      def load_booking_from_cookie
        @booking = current_concierge_booking
      end
    end
  end
end
