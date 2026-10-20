# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      class SourcesController < BaseController
        def show
          return update if request.patch?

          @locked_reason = ::Bookings::ChangeSource.locked_reason(@booking)
          render :show, layout: false
        end

        private

        def update
          result = ::Bookings::ChangeSource.call(booking: @booking, actor: current_user, source: params.dig(:booking, :source))
          return complete_action(notice: "Booking source updated.") if result.success?

          @errors = result.errors
          @locked_reason = ::Bookings::ChangeSource.locked_reason(@booking)
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: turbo_stream.update(
                requesting_sheet_frame,
                partial: "hotel_portal/bookings/actions/sources/form"
              ), status: :unprocessable_content
            end
            format.html { render :show, layout: false, status: :unprocessable_content }
          end
        end
      end
    end
  end
end
