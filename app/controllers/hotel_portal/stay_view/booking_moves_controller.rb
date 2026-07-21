# frozen_string_literal: true

module HotelPortal
  module StayView
    class BookingMovesController < BaseController
      before_action -> { require_capability!(:move_booking) }
      before_action :set_booking

      def edit
        prepare_form
        validate_proposal if pointer_proposal?
      end

      def update
        prepare_form
        check_in = scheduled_date(move_params[:check_in], :check_in)
        room_type_id, room_number = parse_assignment(move_params[:room_assignment])
        room_type = current_hotel.room_types.find(room_type_id)
        raise ArgumentError, "Select a configured room." unless room_type.room_numbers.map(&:to_s).include?(room_number)
        original_room_key = room_key(@original_room.room_type_id, @original_room.room_number)

        result = ::Bookings::UpdateStayService.new(
          booking: @booking,
          params: {
            check_in:,
            check_out: check_in + (@booking.check_out - @booking.check_in),
            room_type_id: room_type.id,
            room_number:
          },
          user: current_user
        ).call

        if result.success?
          return respond_with_board(
            "Stay moved.",
            affected_room_keys: [ original_room_key, room_key(room_type.id, room_number) ]
          )
        end

        add_error(@booking, result.errors)
        render_sheet_error("hotel_portal/stay_view/booking_moves/form")
      rescue ArgumentError => e
        add_error(@booking, e.message)
        render_sheet_error("hotel_portal/stay_view/booking_moves/form")
      end

      private

      def set_booking
        @booking = current_hotel.bookings.includes(booking_rooms: :room_type).find(params[:booking_id])
      end

      def prepare_form
        @original_room = @booking.booking_rooms.first
        @check_in_value = move_params[:check_in].presence || @booking.check_in.in_time_zone(current_hotel.hotel_time_zone).to_date.iso8601
        @room_assignment_value = move_params[:room_assignment].presence || assignment_value(@original_room&.room_type_id, @original_room&.room_number)
        @room_assignment_choices = current_hotel.room_types.order(:name, :id).pluck(:id, :name, :room_numbers).flat_map do |id, name, room_numbers|
          room_numbers.map { |number| { label: "#{name} · Room #{number}", value: assignment_value(id, number) } }
        end
      end

      def move_params
        params.fetch(:booking, {}).permit(:check_in, :room_assignment)
      end

      def scheduled_date(value, kind)
        raise ArgumentError, "Check-in is required." if value.blank?

        ::Bookings::ScheduledStay.at_hotel_time(hotel: current_hotel, value:, kind:)
      end

      def parse_assignment(value)
        room_type_id, room_number = value.to_s.split("|", 2)
        raise ArgumentError, "Room is required." if room_type_id.blank? || room_number.blank?

        [ room_type_id, room_number ]
      end

      def assignment_value(room_type_id, room_number)
        "#{room_type_id}|#{room_number}"
      end

      def validate_proposal
        check_in = scheduled_date(move_params[:check_in], :check_in)
        room_type_id, room_number = parse_assignment(move_params[:room_assignment])
        room_type = current_hotel.room_types.find(room_type_id)
        validate_pointer_proposal(
          booking: @booking,
          room_type:,
          room_number:,
          check_in:,
          check_out: check_in + (@booking.check_out - @booking.check_in)
        )
      rescue ArgumentError => e
        add_error(@booking, e.message)
      end

      def room_key(room_type_id, room_number)
        "#{room_type_id}:#{room_number}"
      end
    end
  end
end
