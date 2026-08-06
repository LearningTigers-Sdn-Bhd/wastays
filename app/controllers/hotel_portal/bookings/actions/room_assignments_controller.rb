# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      # Reassign a stay to a different room category / room number. Per-booking
      # only (siblings are never touched). A Stay View "move" proposal arrives
      # here carrying the proposed room *and* dates.
      class RoomAssignmentsController < BaseController
        include StayEditingForm

        before_action :ensure_eligible!

        def show
          prepare_stay_values
          @room_type_choices = room_type_choices
          @room_choices = room_choices
          return update if request.patch?

          validate_move_proposal if move_proposal?
          render :show, layout: false
        end

        private

        def update
          result = ::Bookings::UpdateStayService.new(
            booking: @booking,
            params: stay_params,
            user: current_user
          ).call

          return complete_action(notice: "Room assignment updated.") if result.success?

          add_errors(result.errors)
          render_failure
        end

        def move_proposal?
          @proposal_kind == "move"
        end

        # Non-mutating pre-save check so an occupied target room or invalid dates
        # surface before the user commits the move.
        def validate_move_proposal
          room_type = current_hotel.room_types.find(@room_type_id)
          add_errors(
            ::Bookings::ValidateStayProposal.call(
              booking: @booking,
              room_type:,
              room_number: @room_number,
              check_in: scheduled_value(@check_in_value, :check_in),
              check_out: scheduled_value(@check_out_value, :check_out)
            )
          )
        rescue ArgumentError, ActiveRecord::RecordNotFound => e
          add_errors(e.message)
        end

        def room_type_choices
          current_hotel.room_types.order(:name, :id).map do |room_type|
            { label: room_type.name, value: room_type.id }
          end
        end

        def room_choices
          room_type = current_hotel.room_types.find_by(id: @room_type_id)
          return [ { label: "Select a room category first", value: "", disabled: true } ] unless room_type

          options = ::Bookings::AvailableRoomNumbers.new(
            hotel: current_hotel,
            room_type:,
            check_in: scheduled_value(@check_in_value, :check_in),
            check_out: scheduled_value(@check_out_value, :check_out),
            exclude_booking_id: @booking.id
          ).options.map do |option|
            { label: option[:label], value: option[:room_number], disabled: !option[:selectable] }
          end
          options.presence || [ { label: "No rooms available", value: "", disabled: true } ]
        rescue ArgumentError
          [ { label: "Choose valid stay dates first", value: "", disabled: true } ]
        end

        # Dates are only carried through when a move proposal shifted them; a plain
        # room change omits the date fields, so they never reach the service.
        def stay_params
          params.fetch(:booking, {}).permit(:room_type_id, :room_number, :check_in, :check_out)
        end

        def render_failure
          prepare_stay_values
          @room_type_choices = room_type_choices
          @room_choices = room_choices
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: turbo_stream.update(
                requesting_sheet_frame,
                partial: "hotel_portal/bookings/actions/room_assignments/form"
              ), status: :unprocessable_content
            end
            format.html { render :show, layout: false, status: :unprocessable_content }
          end
        end
      end
    end
  end
end
