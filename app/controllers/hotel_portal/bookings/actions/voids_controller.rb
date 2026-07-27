# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      class VoidsController < BaseController
        include GroupLifecycleTargeting

        before_action :authorize_void_bookings!

        def show
          return create if request.post?

          render :show, layout: false
        end

        private

        def create
          if void_reason.blank?
            @booking.errors.add(:base, "Void reason is required.")
            return render_void_failure
          end

          return batch_void if selected_lifecycle_batch?(@booking)

          complete_result(void(@booking), notice: "Booking voided. Existing folios were left unchanged.")
        end

        def batch_void
          bookings = selected_lifecycle_bookings(fallback_booking: @booking, action: :void)

          ActiveRecord::Base.transaction do
            bookings.each do |booking|
              result = void(booking)
              raise BatchTargetError, result.error unless result.success?
            end
          end

          complete_action(notice: batch_lifecycle_notice(bookings, "voided; existing folios were left unchanged"))
        rescue BatchTargetError => e
          complete_action(alert: e.message)
        end

        def void(booking)
          ::Bookings::VoidBooking.call(booking:, user: current_user, reason: void_reason)
        end

        def complete_result(result, notice:)
          result.success? ? complete_action(notice:) : complete_action(alert: result.error)
        end

        def void_reason
          params[:void_reason].to_s.strip
        end

        def authorize_void_bookings!
          raise Pundit::NotAuthorizedError unless current_user.has_permission?("void_bookings", hotel: current_hotel)
        end

        def render_void_failure
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: turbo_stream.update(
                requesting_sheet_frame,
                partial: "hotel_portal/bookings/actions/voids/form",
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
