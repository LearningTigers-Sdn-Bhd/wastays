# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      # Sheet-based "reinstate no-show". Reinstates a no-show reservation and
      # re-checks it in against a currently-available room (GET renders the
      # room re-selection form; POST performs the reinstatement).
      #
      # Unlike the multi-select lifecycle actions, group reinstatement is
      # one-booking-at-a-time (radio master-detail): each stay needs its own
      # room/rate re-selection, so siblings are reinstated individually.
      #
      # Business rules live in Bookings::ReinstateReservation /
      # Bookings::ReinstateGroup; this controller only orchestrates
      # authorization, input, rendering, and completion.
      class ReinstatementsController < BaseController
        include GroupLifecycleTargeting

        helper_method :reinstatement_room_options

        def show
          return create if request.post?

          load_group_reinstatement_bookings
          render :show, layout: false
        end

        private

        def create
          if params[:retroactive_reason].blank?
            @booking.errors.add(:base, "Reason for reinstatement is required.")
            return render_reinstatement_failure
          end

          return batch_reinstate if selected_lifecycle_batch?(@booking)

          result = ::Bookings::ReinstateReservation.new(
            booking: @booking,
            params: booking_params.slice(:booking_rooms_attributes),
            user: current_user,
            options: { override_night_audit: true, reason: params[:retroactive_reason] }
          ).call

          if result.success?
            complete_action(notice: "Booking reinstated and checked in successfully.")
          else
            @booking.errors.add(:base, "Failed to reinstate booking: #{result.error}")
            render_reinstatement_failure
          end
        end

        def batch_reinstate
          attributes = batch_reinstatement_params
          selected = selected_lifecycle_bookings(fallback_booking: @booking, action: :reinstate)
          selected_ids = selected.map { |booking| booking.id.to_s }
          raise BatchTargetError, "Every selected booking must be configured before reinstatement." unless (selected_ids - attributes.keys).empty?

          attributes = attributes.slice(*selected_ids)

          result = ::Bookings::ReinstateGroup.call(
            group_booking: @booking.group_booking,
            booking_attributes: attributes,
            user: current_user,
            options: { override_night_audit: true, reason: params[:retroactive_reason] }
          )

          if result.success?
            complete_action(notice: batch_lifecycle_notice(result.bookings, "reinstated and checked in"))
          else
            complete_action(alert: "Failed to reinstate group: #{result.error}")
          end
        rescue BatchTargetError => e
          complete_action(alert: e.message)
        end

        def load_group_reinstatement_bookings
          return unless @booking.group_booking_id?

          @group_reinstatement_bookings = @booking.group_booking.bookings
            .includes(booking_rooms: [ :room_type, :rate_plan ], booking_guests: :guest)
            .order(:group_position, :id)
        end

        # Server-rendered room-number options for a booking room, so the form is
        # accurate on first paint. The reinstate-editor JS refreshes these when
        # the room category changes.
        def reinstatement_room_options(room)
          ::Bookings::AvailableRoomNumbers.new(
            hotel: current_hotel,
            room_type: room.room_type,
            check_in: room.booking.check_in,
            check_out: room.booking.check_out,
            exclude_booking_id: room.booking_id
          ).options
        rescue ArgumentError
          []
        end

        def booking_params
          params.fetch(:booking, {}).permit(
            booking_rooms_attributes: [ :id, :room_type_id, :room_number, :rate_plan_id ]
          )
        end

        def batch_reinstatement_params
          raw = params.fetch(:reinstatements, ActionController::Parameters.new)
          raw.to_unsafe_h.transform_values do |attributes|
            ActionController::Parameters.new(attributes).permit(
              booking_rooms_attributes: [ :id, :room_type_id, :room_number, :rate_plan_id ]
            ).to_h
          end
        end

        def render_reinstatement_failure
          load_group_reinstatement_bookings
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: turbo_stream.update(
                requesting_sheet_frame,
                partial: "hotel_portal/bookings/actions/reinstatements/form",
                locals: { booking: @booking }
              ), status: :unprocessable_content
            end
            format.html { render :show, layout: false, status: :unprocessable_content }
          end
        end
      end
    end
  end
end
