# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      # Edit the booking's guest / contact / source / guarantee details. Migrated
      # from the legacy Offcanvas `transactions/edit_bookings` flow onto the Sheet.
      # Stay logistics (dates, room, rate) live in their own intent Sheets.
      class BookingEditsController < BaseController
        def show
          return update if request.patch?

          render :show, layout: false
        end

        private

        def update
          result = ::Bookings::UpdateStayService.new(
            booking: @booking,
            params: editable_booking_params,
            user: current_user
          ).call

          return complete_action(notice: "Booking details updated.") if result.success?

          result.errors.each { |error| @booking.errors.add(:base, error) }
          render_failure
        end

        def editable_booking_params
          params.fetch(:booking, {}).permit(
            :guest_name, :guest_email, :guest_phone, :guest_country, :guest_gender,
            :guest_document_type, :guest_government_id, :source, :guarantee_method
          )
        end

        def render_failure
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: turbo_stream.update(
                requesting_sheet_frame,
                partial: "hotel_portal/bookings/actions/booking_edits/form"
              ), status: :unprocessable_content
            end
            format.html { render :show, layout: false, status: :unprocessable_content }
          end
        end
      end
    end
  end
end
