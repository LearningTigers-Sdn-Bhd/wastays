# frozen_string_literal: true

module HotelPortal
  module ReservationBoard
    class BoardBookingsController < BaseController
      before_action :authorize_manage_bookings!

      def new
        check_in = params[:check_in].presence || Date.current
        @booking = current_hotel.bookings.build(
          check_in: check_in,
          check_out: params[:check_out].presence || (Date.parse(check_in.to_s) + 2.days),
          adults: 2
        )

        # Pre-select room type if provided
        @room_type_id = params[:room_type_id]
        @room_number = params[:room_number]

        # Calculate initial price if room type is provided
        if @room_type_id.present?
          room_type = current_hotel.room_types.find(@room_type_id)
          @booking.total_amount = ::Bookings::CalculateStayPrice.new(
            room_type: room_type,
            check_in: @booking.check_in,
            check_out: @booking.check_out
          ).call
        end

        @room_types = current_hotel.room_types.order(:name)
        render :new
      end

      def show
        @booking = current_hotel.bookings.find(params[:id])
        @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
        set_audit_logs
      end

      def check_in
        @booking = current_hotel.bookings.includes(booking_rooms: :room_type).find(params[:id])
      end

      def check_out
        @booking = current_hotel.bookings.find(params[:id])
      end

      def edit_stay
        @booking = current_hotel.bookings.find(params[:id])
        @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
        @room_types = current_hotel.room_types.order(:name)
      end

      def notes
        @booking = current_hotel.bookings.find(params[:id])
        @notes = @booking.booking_notes.includes(:user).order(created_at: :desc)
      end

      def update
        @booking = current_hotel.bookings.find(params[:id])

        if @booking.update(booking_params)
          ::Bookings::RecordAuditLog.call(auditable: @booking, user: current_user)

          respond_to do |format|
            format.turbo_stream do
              @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
              set_audit_logs
              render turbo_stream: [
                turbo_stream.replace("reservation_board_booking_sheet_content", template: "hotel_portal/reservation_board/board_bookings/show"),
                turbo_stream.action(:reload, "reservation_board"),
                turbo_stream.append("reservation_board", partial: "shared/toast", locals: { key: "notice", value: "Booking updated successfully." })
              ]
            end
            format.html { redirect_to hotel_reservation_board_index_path(current_hotel), notice: "Booking updated." }
          end
        else
          @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
          @room_types = current_hotel.room_types.order(:name)
          set_audit_logs
          render :show, status: :unprocessable_content
        end
      end

      def create
        result = ::Bookings::CreateManualBooking.new(
          hotel: current_hotel,
          params: booking_params,
          user: current_user
        ).call

        if result.success?
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: [
                turbo_stream.action(:reload, "reservation_board"),
                turbo_stream.append("reservation_board", partial: "shared/toast", locals: { key: "notice", value: "Booking created successfully." })
              ]
            end
            format.html { redirect_to hotel_reservation_board_index_path(current_hotel), notice: "Booking created successfully." }
          end
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

      def set_audit_logs
        # Fetch audit logs for this booking and its related entities
        base_query = BookingAuditLog.where(hotel: current_hotel)

        @audit_logs = base_query.where(auditable: @booking)

        if @booking.booking_quote_id.present?
          @audit_logs = @audit_logs.or(base_query.where(auditable_type: "BookingQuote", auditable_id: @booking.booking_quote_id))
        end

        @audit_logs = @audit_logs.or(base_query.where(auditable_type: "BookingRoom", auditable_id: @booking.booking_rooms.select(:id)))
                                .includes(:user, :auditable)
                                .order(created_at: :desc)
      end

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
