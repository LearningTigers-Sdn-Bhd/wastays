# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      # Reschedule a stay: check-in / check-out dates only. This is the sole
      # Stay-editing Sheet that is group-aware, because `UpdateGroupStay` only
      # ever batches dates across siblings.
      class BookingDatesController < BaseController
        include StayEditingForm

        before_action :ensure_eligible!

        def show
          prepare_stay_values
          return update if request.patch?

          render :show, layout: false
        end

        private

        def update
          return update_group if selected_lifecycle_batch?(@booking)

          result = ::Bookings::UpdateStayService.new(
            booking: @booking,
            params: stay_params,
            user: current_user
          ).call

          return complete_action(notice: "Stay dates updated.") if result.success?

          add_errors(result.errors)
          render_failure
        end

        def update_group
          bookings = selected_lifecycle_bookings(fallback_booking: @booking, action: :amend_stay)
          result = ::Bookings::UpdateGroupStay.call(
            group_booking: @booking.group_booking,
            booking_ids: bookings.map(&:id),
            params: stay_params,
            user: current_user
          )

          if result.success?
            complete_action(notice: batch_lifecycle_notice(result.bookings, "stay dates updated"))
          else
            add_errors(result.error)
            render_failure
          end
        rescue BatchTargetError => e
          add_errors(e.message)
          render_failure
        end

        def stay_params
          params.fetch(:booking, {}).permit(:check_in, :check_out)
        end

        def render_failure
          prepare_stay_values
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: turbo_stream.update(
                requesting_sheet_frame,
                partial: "hotel_portal/bookings/actions/booking_dates/form"
              ), status: :unprocessable_content
            end
            format.html { render :show, layout: false, status: :unprocessable_content }
          end
        end
      end
    end
  end
end
