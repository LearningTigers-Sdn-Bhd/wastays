# frozen_string_literal: true

module HotelPortal
  module ReservationBoard
    class BookingsController < BaseController
      before_action :authorize_manage_bookings!

      def new
        @booking = current_hotel.bookings.build(
          check_in: params[:check_in].presence || Date.current,
          check_out: params[:check_out].presence || Date.current + 1.day,
          adults: 2
        )

        # Pre-select room type if provided
        @room_type_id = params[:room_type_id]
        @room_number = params[:room_number]

        @room_types = current_hotel.room_types.order(:name)
        render :new
      end

      def show
        @booking = current_hotel.bookings.find(params[:id])
        @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
      end

      def create
        result = ::Bookings::CreateManualBooking.new(
          hotel: current_hotel,
          params: booking_params,
          user: current_user
        ).call

        if result.success?
          redirect_to hotel_reservation_board_index_path(current_hotel), notice: "Booking created successfully."
        else
          @booking = current_hotel.bookings.build(booking_params.except(:room_type_id, :room_number))
          @room_types = current_hotel.room_types.order(:name)
          flash.now[:alert] = result.errors.to_sentence
          render :new, status: :unprocessable_content
        end
      end

      def transition
        @booking = current_hotel.bookings.find(params[:id])
        result = ::Bookings::TransitionStatus.new(
          booking: @booking,
          status: params[:status],
          user: current_user
        ).call

        if result.success?
          respond_to do |format|
            format.turbo_stream { render turbo_stream: turbo_stream.action(:reload, "reservation_board") }
            format.html { redirect_to hotel_reservation_board_index_path(current_hotel), notice: "Booking status updated." }
          end
        else
          respond_to do |format|
            format.turbo_stream { render turbo_stream: turbo_stream.append("reservation_board", partial: "shared/toast", locals: { key: "alert", value: result.error }) }
            format.html { redirect_to hotel_reservation_board_index_path(current_hotel), alert: result.error }
          end
        end
      end

      private

      def booking_params
        params.fetch(:booking, {}).permit(
          :guest_name, :guest_email, :guest_phone, :status,
          :room_type_id, :room_number, :check_in, :check_out, :adults, :children, :total_amount
        )
      end

      def authorize_manage_bookings!
        raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
      end
    end
  end
end
