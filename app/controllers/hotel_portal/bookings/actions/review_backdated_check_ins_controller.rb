# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      # Sheet-based backdated check-in for an EXISTING booking under no-show
      # review. Renders the form into the requesting Sheet frame (GET) and
      # transitions the booking to checked_in with a backdated timestamp (POST),
      # supporting single and group batch targeting.
      #
      # The NEW-booking backdated flow lives in BackdatedCheckInsController.
      # Business rules live in Bookings::TransitionStatus; this controller only
      # orchestrates authorization, input, rendering, and completion.
      class ReviewBackdatedCheckInsController < BaseController
        include GroupLifecycleTargeting

        def show
          return create if request.post?

          render :show, layout: false
        end

        private

        def create
          unless selected_lifecycle_batch?(@booking) || @booking.status == "no_show_detected"
            return complete_action(alert: "Backdated check-in is only available while reviewing a missed arrival.")
          end

          if reason_error
            @booking.errors.add(:base, reason_error)
            return render_backdated_failure
          end

          return batch_backdated_check_in if selected_lifecycle_batch?(@booking)

          result = transition(@booking, timestamp: booking_params[:checked_in_at].presence || @booking.check_in)

          if result.success?
            complete_action(notice: "Backdated check-in completed.")
          else
            complete_action(alert: result.error)
          end
        end

        def batch_backdated_check_in
          bookings = selected_lifecycle_bookings(fallback_booking: @booking, action: :backdated_check_in)

          ActiveRecord::Base.transaction do
            bookings.each do |booking|
              result = transition(booking, timestamp: booking.check_in)
              raise BatchTargetError, result.error unless result.success?
            end
          end

          complete_action(notice: batch_lifecycle_notice(bookings, "backdated checked in"))
        rescue BatchTargetError => e
          complete_action(alert: e.message)
        end

        def transition(booking, timestamp:)
          ::Bookings::TransitionStatus.new(
            booking: booking,
            status: "checked_in",
            timestamp: timestamp,
            user: current_user,
            options: {
              override_night_audit: true,
              reason: params[:retroactive_reason].presence || params[:backdate_reason],
              backdate_reason_category: params[:backdate_reason],
              backdate_reason_details: params[:retroactive_reason]
            }
          ).call
        end

        def reason_error
          if params[:backdate_reason] == "Other" && params[:retroactive_reason].blank?
            "Please provide details for the backdated check-in reason."
          elsif params[:backdate_reason].blank? && params[:retroactive_reason].blank?
            "Backdated check-in reason is required."
          end
        end

        def booking_params
          params.fetch(:booking, {}).permit(:checked_in_at)
        end

        def render_backdated_failure
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: turbo_stream.update(
                requesting_sheet_frame,
                partial: "hotel_portal/bookings/actions/review_backdated_check_ins/form",
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
