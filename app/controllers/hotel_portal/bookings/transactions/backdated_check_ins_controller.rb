# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Transactions
      class BackdatedCheckInsController < BaseController
        before_action :set_booking, if: -> { params[:booking_id].present? && request.get? }

        def show
          return submit if request.post?

          if @booking
            return redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details"), alert: "Backdated check-in is only available while reviewing a missed arrival." unless @booking.status == "review_no_show"

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

          unless params[:booking_id].present?
            result = create_staff_booking(booking_type: "backdated_check_in")
            return complete_new_booking(result.booking, notice: result.group_booking ? "Backdated group check-in completed." : "Backdated check-in completed.") if result.success?

            @booking = current_hotel.bookings.build(model_booking_params.merge(source: "walk_in"))
            result.errors.each { |error| @booking.errors.add(:base, error) }
            render_new_booking(transaction: :backdated_check_in, status: :unprocessable_content)
            return
          end

          booking = current_hotel.bookings.find(params[:booking_id])
          return unless booking
          if params[:booking_id].present? && booking.status != "review_no_show"
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
