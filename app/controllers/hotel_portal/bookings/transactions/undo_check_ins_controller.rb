# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Transactions
      class UndoCheckInsController < BaseController
        before_action :set_booking, only: [ :show ]

        def show
          return submit if request.post?

          if @booking.status != "checked_in"
            return redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details"), alert: "Undo check-in is only available for checked-in bookings."
          end

          render "hotel_portal/bookings/transactions/undo_check_in/offcanvas"
        end

        private

        def submit
          booking = current_hotel.bookings.find(params[:booking_id])
          if params[:retroactive_reason].blank?
            return redirect_to hotel_booking_control_panel_path(current_hotel, booking, tab: "booking_details"), alert: "Reason to change is required."
          end

          if selected_lifecycle_batch?(booking)
            return batch_undo_check_in(booking)
          end

          result = ::Bookings::TransitionStatus.new(
            booking: booking,
            status: "confirmed",
            user: current_user,
            options: {
              event: "undo_check_in",
              reason: params[:retroactive_reason]
            }
          ).call

          if result.success?
            redirect_to hotel_booking_control_panel_path(current_hotel, booking, tab: "booking_details"), notice: "Check-in undone successfully."
          else
            redirect_to hotel_booking_control_panel_path(current_hotel, booking, tab: "booking_details"), alert: result.error
          end
        end

        def batch_undo_check_in(booking)
          bookings = selected_lifecycle_bookings(fallback_booking: booking, action: :undo_check_in)

          ActiveRecord::Base.transaction do
            bookings.each do |b|
              result = ::Bookings::TransitionStatus.new(
                booking: b,
                status: "confirmed",
                user: current_user,
                options: {
                  event: "undo_check_in",
                  reason: params[:retroactive_reason]
                }
              ).call
              raise BatchTargetError, result.error unless result.success?
            end
          end

          offcanvas_transaction_response(
            destination: offcanvas_return_to(fallback: hotel_booking_control_panel_path(current_hotel, booking, tab: "booking_details")),
            notice: batch_lifecycle_notice(bookings, "check-in undone")
          )
        rescue BatchTargetError => e
          redirect_to hotel_booking_control_panel_path(current_hotel, booking, tab: "booking_details"), alert: e.message, status: :see_other
        end
      end
    end
  end
end
