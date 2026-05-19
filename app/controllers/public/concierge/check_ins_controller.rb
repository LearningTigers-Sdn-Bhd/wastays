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
          if booking.pre_checkin&.completed? || past_check_in_time?(booking)
            set_concierge_booking_cookie(booking)
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

        if needs_registration?
          unless save_guest_registration
            @error_code = :registration_error
            render :check_in_now, status: :unprocessable_content
            return
          end
        end

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

      def needs_registration?
        @booking.pre_checkin.nil? || !@booking.pre_checkin.completed?
      end

      def save_guest_registration
        permitted = params.require(:booking).permit(
          :guest_name,
          :guest_email,
          :guest_phone,
          :guest_country,
          :guest_document_type,
          :guest_government_id,
          :guest_home_address
        )
        @booking.update(permitted)
      rescue ActionController::ParameterMissing
        false
      end

      def past_check_in_time?(booking)
        policy = booking.hotel.property_policy
        return false if policy&.check_in_time.blank?
        return false if Time.zone.today < booking.check_in.to_date
        return true if Time.zone.today > booking.check_in.to_date

        check_in_dt = Time.zone.parse("#{Time.zone.today} #{policy.check_in_time}")
        return false unless check_in_dt

        Time.current >= check_in_dt
      rescue ArgumentError, TypeError
        false
      end
    end
  end
end
