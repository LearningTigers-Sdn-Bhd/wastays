# frozen_string_literal: true

module HotelPortal
  module StayView
    class BookingDatesController < BaseController
      before_action -> { require_capability!(:change_dates) }
      before_action :set_booking

      def edit
        prepare_form
      end

      def update
        prepare_form
        check_in = scheduled_date(date_params[:check_in], :check_in)
        check_out = scheduled_date(date_params[:check_out], :check_out)
        raise ArgumentError, "Checkout must be after check-in." unless check_out > check_in

        result = ::Bookings::UpdateStayService.new(
          booking: @booking,
          params: { check_in:, check_out: },
          user: current_user
        ).call

        return respond_with_board("Stay dates changed.") if result.success?

        add_error(@booking, result.errors)
        render_sheet_error("hotel_portal/stay_view/booking_dates/form")
      rescue ArgumentError => e
        add_error(@booking, e.message)
        render_sheet_error("hotel_portal/stay_view/booking_dates/form")
      end

      private

      def set_booking
        @booking = current_hotel.bookings.includes(booking_rooms: :room_type).find(params[:booking_id])
      end

      def prepare_form
        zone = current_hotel.hotel_time_zone
        @check_in_value = date_params[:check_in].presence || @booking.check_in.in_time_zone(zone).to_date.iso8601
        @check_out_value = date_params[:check_out].presence || @booking.check_out.in_time_zone(zone).to_date.iso8601
      end

      def date_params
        params.fetch(:booking, {}).permit(:check_in, :check_out)
      end

      def scheduled_date(value, kind)
        raise ArgumentError, "#{kind.to_s.humanize} is required." if value.blank?

        ::Bookings::ScheduledStay.at_hotel_time(hotel: current_hotel, value:, kind:)
      end
    end
  end
end
