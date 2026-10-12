# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      class RoomChargeCorrectionsController < BaseController
        before_action :authorize_correction!

        def show
          prepare_form
          render :show, layout: false
        end

        def review
          prepare_form
          return render_sheet if params[:back].present?

          handle_result(correction(confirm: false))
        end

        def confirm
          prepare_form
          handle_result(correction(confirm: true))
        end

        private

        def authorize_correction!
          raise Pundit::NotAuthorizedError unless ::Bookings::CorrectRoomCharges.available?(booking: @booking, user: current_user)
        end

        def prepare_form
          @room = @booking.booking_rooms.first
          values = correction_params
          @nightly_amounts = values[:nightly_amounts].to_h
          @correction_reason = values[:correction_reason]
          @currency = @booking.currency.presence || current_hotel.default_currency
          @nights = current_nights
        end

        def current_nights
          ::Bookings::BuildRoomChargeCorrectionSnapshot.new(booking: @booking, nightly_amounts: {}).current_nights
        rescue ArgumentError => e
          @errors = [ e.message ]
          []
        end

        def correction(confirm:)
          ::Bookings::CorrectRoomCharges.call(booking: @booking, user: current_user, confirm: confirm, **correction_params.to_h.symbolize_keys)
        end

        def correction_params
          params.fetch(:room_charge_correction, ActionController::Parameters.new).permit(:correction_reason, :correction_review_token, nightly_amounts: {})
        end

        def handle_result(result)
          return complete_action(notice: "Room charges corrected. Settle and close affected folios to finalize any revised invoices.") if result.success?

          @review = result.review
          @review_token = result.correction_review_token
          @review_message = result.review_message
          @errors = result.errors.presence || @errors || []
          render_sheet(status: @errors.any? ? :unprocessable_content : :ok)
        end

        def render_sheet(status: :ok)
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: turbo_stream.update(requesting_sheet_frame,
                partial: "hotel_portal/bookings/actions/room_charge_corrections/form"), status: status
            end
            format.html { render :show, layout: false, status: status }
          end
        end
      end
    end
  end
end
