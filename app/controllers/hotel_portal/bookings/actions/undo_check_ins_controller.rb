# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      # Sheet-based "undo check-in". Renders the confirmation form into the
      # requesting Sheet frame (GET) and reverts the booking to confirmed (POST),
      # supporting single and group batch targeting.
      #
      # Business rules live in Bookings::TransitionStatus; this controller only
      # orchestrates authorization, input, rendering, and completion.
      class UndoCheckInsController < BaseController
        include GroupLifecycleTargeting

        def show
          return create if request.post?

          render :show, layout: false
        end

        private

        def create
          unless selected_lifecycle_batch?(@booking) || @booking.status == "checked_in"
            return complete_action(alert: "Undo check-in is only available for checked-in bookings.")
          end

          if retroactive_reason.blank?
            @booking.errors.add(:base, "Reason to change is required.")
            return render_undo_failure
          end

          return batch_undo_check_in if selected_lifecycle_batch?(@booking)

          result = transition(@booking)

          if result.success?
            complete_action(notice: "Check-in undone successfully.")
          else
            complete_action(alert: result.error)
          end
        end

        def batch_undo_check_in
          bookings = selected_lifecycle_bookings(fallback_booking: @booking, action: :undo_check_in)

          ActiveRecord::Base.transaction do
            bookings.each do |booking|
              result = transition(booking)
              raise BatchTargetError, result.error unless result.success?
            end
          end

          complete_action(notice: batch_lifecycle_notice(bookings, "check-in undone"))
        rescue BatchTargetError => e
          complete_action(alert: e.message)
        end

        def transition(booking)
          ::Bookings::TransitionStatus.new(
            booking: booking,
            status: "confirmed",
            user: current_user,
            options: { event: "undo_check_in", reason: retroactive_reason }
          ).call
        end

        def retroactive_reason
          params[:retroactive_reason].to_s.strip
        end

        def render_undo_failure
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: turbo_stream.update(
                requesting_sheet_frame,
                partial: "hotel_portal/bookings/actions/undo_check_ins/form",
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
