# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Transactions
      class BackdatedCheckInsController < BaseController
        before_action :set_booking, if: -> { request.get? }

        def show
          return submit if request.post?

          return redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details"), alert: "Backdated check-in is only available while reviewing a missed arrival." unless @booking.status == "review_no_show"

          render "hotel_portal/bookings/transactions/backdated_check_in/offcanvas"
        end

        private

        def submit
          if params[:backdate_reason] == "Other" && params[:retroactive_reason].blank?
            return redirect_back fallback_location: hotel_front_desk_path(current_hotel, tab: "bookings", view: "list"), alert: "Please provide details for the backdated check-in reason."
          elsif params[:backdate_reason].blank? && params[:retroactive_reason].blank?
            return redirect_back fallback_location: hotel_front_desk_path(current_hotel, tab: "bookings", view: "list"), alert: "Backdated check-in reason is required."
          end

          booking = current_hotel.bookings.find(params[:booking_id])
          if booking.status != "review_no_show"
            return redirect_to hotel_booking_control_panel_path(current_hotel, booking, tab: "booking_details"), alert: "Backdated check-in is only available while reviewing a missed arrival."
          end

          if selected_lifecycle_batch?(booking)
            return batch_backdated_check_in(booking)
          end

          result = ::Bookings::TransitionStatus.new(
            booking: booking,
            status: "checked_in",
            timestamp: booking_params[:checked_in_at].presence || booking.check_in,
            user: current_user,
            options: {
              override_night_audit: true,
              reason: params[:retroactive_reason].presence || params[:backdate_reason],
              backdate_reason_category: params[:backdate_reason],
              backdate_reason_details: params[:retroactive_reason]
            }
          ).call

          return complete_existing_booking(booking, notice: "Backdated check-in completed.") if result.success?

          redirect_to hotel_booking_control_panel_path(current_hotel, booking, tab: "booking_details"), alert: result.error
        end

        def batch_backdated_check_in(booking)
          bookings = selected_lifecycle_bookings(fallback_booking: booking, action: :backdated_check_in)

          ActiveRecord::Base.transaction do
            bookings.each do |target_booking|
              result = ::Bookings::TransitionStatus.new(
                booking: target_booking,
                status: "checked_in",
                timestamp: target_booking.check_in,
                user: current_user,
                options: {
                  override_night_audit: true,
                  reason: params[:retroactive_reason].presence || params[:backdate_reason],
                  backdate_reason_category: params[:backdate_reason],
                  backdate_reason_details: params[:retroactive_reason]
                }
              ).call
              raise BatchTargetError, result.error unless result.success?
            end
          end

          complete_existing_booking(booking, notice: batch_lifecycle_notice(bookings, "backdated checked in"))
        rescue BatchTargetError => e
          redirect_to hotel_booking_control_panel_path(current_hotel, booking, tab: "booking_details"), alert: e.message, status: :see_other
        end
      end
    end
  end
end
