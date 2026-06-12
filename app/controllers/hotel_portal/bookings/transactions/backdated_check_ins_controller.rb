# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Transactions
      class BackdatedCheckInsController < BaseController
        before_action :set_booking, if: -> { params[:booking_id].present? && request.get? }

        def show
          return submit if request.post?

          if @booking
            render "hotel_portal/bookings/transactions/backdated_check_in/offcanvas"
          else
            build_booking(source: "walk_in")
            render_new_booking(transaction: :backdated_check_in)
          end
        end

        private

        def submit
          return redirect_back fallback_location: hotel_bookings_path(current_hotel), alert: "Backdated check-in reason is required." if params[:retroactive_reason].blank?

          booking = params[:booking_id].present? ? current_hotel.bookings.find(params[:booking_id]) : create_backdated_walk_in
          return unless booking

          result = ::Bookings::TransitionStatus.new(
            booking: booking,
            status: "checked_in",
            timestamp: booking_params[:checked_in_at].presence || booking.check_in,
            user: current_user,
            options: { override_night_audit: true, reason: params[:retroactive_reason] }
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
