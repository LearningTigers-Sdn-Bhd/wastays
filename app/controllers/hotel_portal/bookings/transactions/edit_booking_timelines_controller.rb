# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Transactions
      class EditBookingTimelinesController < BaseController
        TIMELINE_ACTIONS = %w[move extend].freeze

        before_action :set_booking
        before_action :set_timeline_action
        before_action :set_original_values

        def show
          return head :unprocessable_content unless @timeline_action

          prepare_form_values
          return update if request.patch?

          render_timeline_sheet
        end

        private

        def update
          result = ::Bookings::UpdateStayService.new(
            booking: @booking,
            params: timeline_update_params,
            user: current_user
          ).call

          return complete_existing_booking(@booking, notice: success_notice) if result.success?

          result.errors.each { |error| @booking.errors.add(:base, error) }
          prepare_form_values
          render_timeline_sheet(status: :unprocessable_content)
        rescue ArgumentError => e
          @booking.errors.add(:base, e.message)
          prepare_form_values
          render_timeline_sheet(status: :unprocessable_content)
        end

        def set_timeline_action
          @timeline_action = params[:timeline_action].presence_in(TIMELINE_ACTIONS)
        end

        def set_original_values
          @original_check_in = @booking.check_in
          @original_check_out = @booking.check_out
          @original_room = @booking.booking_rooms.first
        end

        def prepare_form_values
          @room_types = current_hotel.room_types.order(:name)
          @proposed_check_in = scheduled_value(params[:check_in], :check_in) || @booking.check_in
          @proposed_check_out = scheduled_value(params[:check_out], :check_out) || @booking.check_out
          @proposed_room_type_id = params[:room_type_id].presence || @original_room&.room_type_id
          @proposed_room_number = params[:room_number].presence || @original_room&.room_number
        end

        def timeline_update_params
          case @timeline_action
          when "move"
            move_update_params
          when "extend"
            extend_update_params
          end
        end

        def move_update_params
          check_in = scheduled_value(timeline_params[:check_in], :check_in)
          raise ArgumentError, "Check-in is required." unless check_in
          raise ArgumentError, "Room category is required." if timeline_params[:room_type_id].blank?
          raise ArgumentError, "Room number is required." if timeline_params[:room_number].blank?

          {
            check_in: check_in,
            check_out: check_in + (@original_check_out - @original_check_in),
            room_type_id: timeline_params[:room_type_id],
            room_number: timeline_params[:room_number]
          }
        end

        def extend_update_params
          check_out = scheduled_value(timeline_params[:check_out], :check_out)
          raise ArgumentError, "Check-out is required." unless check_out
          raise ArgumentError, "New check-out must be later than the current check-out." unless check_out > @original_check_out

          { check_out: check_out }
        end

        def timeline_params
          params.fetch(:booking, {}).permit(:check_in, :check_out, :room_type_id, :room_number)
        end

        def scheduled_value(value, kind)
          return if value.blank?

          ::Bookings::ScheduledStay.at_hotel_time(hotel: current_hotel, value: value, kind: kind)
        end

        def render_timeline_sheet(status: :ok)
          render "hotel_portal/bookings/transactions/edit_booking_timeline/offcanvas", status: status
        end

        def success_notice
          @timeline_action == "move" ? "Booking moved successfully." : "Stay extended successfully."
        end
      end
    end
  end
end
