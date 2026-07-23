# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      # Sheet-based backdated check-in for a NEW booking (no existing booking).
      # The review-no-show / existing-booking backdated flow remains on the
      # legacy Transactions implementation.
      class BackdatedCheckInsController < BookingCreationBaseController
        def show
          return create if request.post?

          build_booking(source: "walk_in")
          render_new_booking(transaction: :backdated_check_in)
        end

        private

        def create
          if reason_missing?
            message = backdate_reason == "Other" ? "Please provide details for the backdated check-in reason." : "Backdated check-in reason is required."
            return render_new_booking_failure(transaction: :backdated_check_in, errors: [ message ])
          end

          result = create_staff_booking(booking_type: "backdated_check_in")
          return complete_new_booking(result.booking, notice: result.group_booking ? "Backdated group check-in completed." : "Backdated check-in completed.") if result.success?

          render_new_booking_failure(transaction: :backdated_check_in, errors: result.errors)
        end

        # The creation form posts the reason under booking[backdate_reason]; keep a
        # top-level fallback for older callers.
        def backdate_reason
          booking_params[:backdate_reason].presence || params[:backdate_reason]
        end

        def reason_missing?
          (backdate_reason == "Other" && params[:retroactive_reason].blank?) ||
            (backdate_reason.blank? && params[:retroactive_reason].blank?)
        end
      end
    end
  end
end
