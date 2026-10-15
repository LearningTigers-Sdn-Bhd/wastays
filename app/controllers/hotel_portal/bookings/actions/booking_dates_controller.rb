# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      # Reschedule a stay: check-in / check-out dates only. This is the sole
      # Stay-editing Sheet that is group-aware. Date correction reviews cover
      # every selected sibling before the batch can be confirmed.
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

          result = ::Bookings::UpdateStayDates.call(
            bookings: [ @booking ], params: stay_params, user: current_user, **correction_params
          )
          handle_result(result)
        end

        def update_group
          bookings = selected_lifecycle_bookings(fallback_booking: @booking, action: :amend_stay)
          result = ::Bookings::UpdateStayDates.call(
            bookings: bookings, params: stay_params, user: current_user, **correction_params
          )
          handle_result(result, group: true)
        rescue BatchTargetError => e
          add_errors(e.message)
          render_failure
        end

        def handle_result(result, group: false)
          if result.success?
            notice = if group
              batch_lifecycle_notice(result.bookings, result.corrected? ? "stay dates and charges updated" : "stay dates updated")
            else
              result.corrected? ? "Stay dates and charges updated." : "Stay dates updated."
            end
            return complete_action(notice: notice)
          end

          @booking.reload
          @correction_review = result.correction_review
          @correction_review_token = result.correction_review_token
          @correction_allowed = result.correction_allowed?
          @correction_review_message = result.review_message
          add_errors(result.errors)
          render_failure(status: result.errors.any? ? :unprocessable_content : :ok)
        end

        def correction_params
          params.fetch(:booking, {}).permit(:correction_reason, :correction_review_token).to_h.symbolize_keys
        end

        def stay_params
          params.fetch(:booking, {}).permit(:check_in, :check_out)
        end

        def render_failure(status: :unprocessable_content)
          prepare_stay_values
          review = @correction_review&.find { |item| item[:booking_id] == @booking.id }
          if review
            @proposed_room_total = review[:proposed_room_total]
            @proposed_tax_total = review[:proposed_tax_total]
            @proposed_total_amount = review[:proposed_total_amount]
          end
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: turbo_stream.update(
                requesting_sheet_frame,
                partial: "hotel_portal/bookings/actions/booking_dates/form"
              ), status: status
            end
            format.html { render :show, layout: false, status: status }
          end
        end
      end
    end
  end
end
