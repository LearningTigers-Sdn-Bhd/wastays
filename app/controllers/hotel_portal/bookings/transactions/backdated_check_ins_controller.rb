# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Transactions
      class BackdatedCheckInsController < BaseController
        before_action :set_booking, if: -> { params[:booking_id].present? && request.get? }

        def show
          return submit if request.post?

          if @booking
            return redirect_to hotel_booking_path(current_hotel, @booking), alert: "Backdated check-in is only available while reviewing a missed arrival." unless @booking.status == "review_no_show"

            render "hotel_portal/bookings/transactions/backdated_check_in/offcanvas"
          else
            build_booking(source: "walk_in")
            render_new_booking(transaction: :backdated_check_in)
          end
        end

        private

        def submit
          if params[:backdate_reason] == "Other" && params[:retroactive_reason].blank?
            return redirect_back fallback_location: hotel_bookings_path(current_hotel), alert: "Please provide details for the backdated check-in reason."
          elsif params[:backdate_reason].blank? && params[:retroactive_reason].blank?
            return redirect_back fallback_location: hotel_bookings_path(current_hotel), alert: "Backdated check-in reason is required."
          end

          booking = params[:booking_id].present? ? current_hotel.bookings.find(params[:booking_id]) : create_backdated_walk_in
          return unless booking
          if params[:booking_id].present? && booking.status != "review_no_show"
            return redirect_to hotel_booking_path(current_hotel, booking), alert: "Backdated check-in is only available while reviewing a missed arrival."
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
              backdate_reason_details: params[:retroactive_reason],
              posting_date: params[:posting_date]
            }
          ).call

          return complete_existing_booking(booking, notice: "Backdated check-in completed.") if result.success?

          redirect_to hotel_booking_path(current_hotel, booking), alert: result.error
        end

        def create_backdated_walk_in
          result = create_manual_booking(source: "walk_in")
          return result.booking if result.success?

          @booking = current_hotel.bookings.build(model_booking_params.merge(source: "walk_in"))
          result.errors.each { |error| @booking.errors.add(:base, error) }
          render_new_booking(transaction: :backdated_check_in, status: :unprocessable_content)
          nil
        end
      end
    end
  end
end
