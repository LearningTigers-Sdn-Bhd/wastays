# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      # Reprice a stay: rate plan / tier selection. Per-booking only. Manual
      # override preservation and financial recalculation are owned by
      # UpdateStayService.
      class RateChangesController < BaseController
        include StayEditingForm

        before_action :ensure_eligible!

        def show
          prepare_stay_values
          @rate_choices = rate_choices
          return update if request.patch?

          render :show, layout: false
        end

        private

        def update
          result = ::Bookings::UpdateStayService.new(
            booking: @booking,
            params: stay_params,
            user: current_user
          ).call

          return complete_action(notice: "Rate updated.") if result.success?

          add_errors(result.errors)
          render_failure
        end

        def rate_choices
          room_type = @room&.room_type
          return [ { label: "No rates available", value: "", disabled: true } ] unless room_type

          options = ::Bookings::RateOptions.new(
            room_type:,
            check_in: Date.parse(@check_in_value),
            check_out: Date.parse(@check_out_value)
          ).call
          options.map do |option|
            label = "#{option[:name]} · #{option[:currency]} #{format('%.2f', option[:total_amount].to_d)}"
            { label:, value: option[:id].to_s }
          end.presence || [ { label: "No rates available", value: "", disabled: true } ]
        rescue ArgumentError, Date::Error
          [ { label: "Choose valid stay dates first", value: "", disabled: true } ]
        end

        def stay_params
          params.fetch(:booking, {}).permit(:rate_selection)
        end

        def render_failure
          prepare_stay_values
          @rate_choices = rate_choices
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: turbo_stream.update(
                requesting_sheet_frame,
                partial: "hotel_portal/bookings/actions/rate_changes/form"
              ), status: :unprocessable_content
            end
            format.html { render :show, layout: false, status: :unprocessable_content }
          end
        end
      end
    end
  end
end
