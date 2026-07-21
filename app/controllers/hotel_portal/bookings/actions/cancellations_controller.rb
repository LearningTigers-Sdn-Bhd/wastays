# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      # Sheet-based booking cancellation. Renders the cancellation form into the
      # requesting Sheet frame (GET) and performs the cancellation (POST),
      # supporting single and group batch targeting.
      #
      # Business rules live in Bookings::TransitionStatus; this controller only
      # orchestrates authorization, input, rendering, and completion.
      class CancellationsController < BaseController
        include GroupLifecycleTargeting

        def show
          return create if request.post?

          render :show, layout: false
        end

        private

        def create
          if params[:cancellation_reason].blank?
            @booking.errors.add(:base, "Cancellation reason is required.")
            return render_cancellation_failure
          end

          return batch_cancel if selected_lifecycle_batch?(@booking)

          result = transition(@booking)

          if result.success?
            complete_action(notice: "Booking cancelled successfully.")
          else
            complete_action(alert: result.error)
          end
        end

        def batch_cancel
          bookings = selected_lifecycle_bookings(fallback_booking: @booking, action: :cancel)

          ActiveRecord::Base.transaction do
            bookings.each do |booking|
              result = transition(booking)
              raise BatchTargetError, result.error unless result.success?
            end
          end

          complete_action(notice: batch_lifecycle_notice(bookings, "cancelled"))
        rescue BatchTargetError => e
          complete_action(alert: e.message)
        end

        def transition(booking)
          ::Bookings::TransitionStatus.new(
            booking: booking,
            status: "cancelled",
            user: current_user,
            options: { reason: params[:cancellation_reason] }
          ).call
        end

        def render_cancellation_failure
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: turbo_stream.update(
                requesting_sheet_frame,
                partial: "hotel_portal/bookings/actions/cancellations/form",
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
