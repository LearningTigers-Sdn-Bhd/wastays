# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Transactions
      class AmendStaysController < BaseController
        include GroupLifecycleTargeting

        before_action :set_booking

        def show
          @room_types = current_hotel.room_types.order(:name)
          return update if request.patch?

          render "hotel_portal/bookings/transactions/amend_stay/offcanvas"
        end

        private

        def update
          if selected_lifecycle_batch?(@booking)
            begin
              bookings = selected_lifecycle_bookings(fallback_booking: @booking, action: :amend_stay)
              result = ::Bookings::UpdateGroupStay.call(
                group_booking: @booking.group_booking,
                booking_ids: bookings.map(&:id),
                params: amend_stay_params,
                user: current_user
              )

              if result.success?
                return complete_existing_booking(@booking, notice: batch_lifecycle_notice(result.bookings, "stay amended"))
              else
                raise BatchTargetError, result.error
              end
            rescue BatchTargetError => e
              return redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details"), alert: e.message, status: :see_other
            end
          end

          result = ::Bookings::UpdateStayService.new(booking: @booking, params: amend_stay_params, user: current_user).call
          if result.success?
            return complete_existing_booking(@booking, notice: "Stay amended successfully.")
          end

          @booking.errors.add(:base, result.errors.to_sentence)
          @room_types = current_hotel.room_types.order(:name)
          render "hotel_portal/bookings/transactions/amend_stay/offcanvas", status: :unprocessable_content
        end

        def amend_stay_params
          booking_params.slice(
            :check_in, :check_out, :adults, :children, :room_type_id, :room_number,
            :rate_plan_id, :total_amount, :manual_rate_override
          )
        end
      end
    end
  end
end
