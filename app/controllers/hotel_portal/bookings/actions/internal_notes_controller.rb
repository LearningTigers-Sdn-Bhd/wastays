# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      class InternalNotesController < BaseController
        MODES = %w[add edit history].freeze

        before_action :set_mode, only: :show
        before_action :set_note, if: -> { action_name == "show" && @mode != "add" }
        before_action :set_deleted_note, only: :delete

        def show
          return create if request.post? && @mode == "add"
          return update if request.patch? && @mode == "edit"
          raise ActiveRecord::RecordNotFound unless request.get? || request.head?

          @note ||= @booking.booking_notes.build
          render :show, layout: false
        end

        def delete
          return destroy if request.delete?

          render :delete, layout: false
        end

        private

        def set_mode
          @mode = params[:mode].presence_in(MODES)
          @mode = "add" if params[:mode].blank?
          raise ActiveRecord::RecordNotFound unless @mode
        end

        def set_note
          @note = @booking.booking_notes.find(params[:note_id])
        end

        def set_deleted_note
          @note = @booking.booking_notes.find(params[:note_id])
        end

        def create
          result = ::Bookings::CreateBookingNote.call(booking: @booking, actor: current_user, body: note_params[:body])
          @note = result.note
          return complete_note_action(notice: "Note added.") if result.success?

          add_errors(@note, result.errors)
          render_note_failure
        end

        def update
          result = ::Bookings::UpdateBookingNote.call(note: @note, actor: current_user, body: note_params[:body])
          @note = result.note
          return complete_note_action(notice: "Note updated.") if result.success?

          add_errors(@note, result.errors)
          render_note_failure
        end

        def destroy
          result = ::Bookings::DeleteBookingNote.call(note: @note, actor: current_user)
          result.success? ? complete_note_action(notice: "Note deleted.") : complete_action(alert: result.errors.to_sentence)
        end

        def complete_note_action(notice:)
          respond_to do |format|
            format.turbo_stream do
              flash[:notice] = notice
              @booking.reload
              render turbo_stream: [
                turbo_stream.replace(
                  "booking_internal_notes",
                  partial: "hotel_portal/booking_control_panels/booking_details/internal_notes",
                  locals: { booking: @booking }
                ),
                helpers.turbo_stream_action_tag(
                  :complete_sheet,
                  target: requesting_sheet_frame,
                  url: @return_to
                )
              ]
            end
            format.html { redirect_to @return_to, notice:, status: :see_other }
          end
        end

        def render_note_failure
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: turbo_stream.update(
                requesting_sheet_frame,
                partial: "hotel_portal/bookings/actions/internal_notes/form"
              ), status: :unprocessable_content
            end
            format.html { render :show, layout: false, status: :unprocessable_content }
          end
        end

        def add_errors(record, errors)
          errors.each { |error| record.errors.add(:base, error) unless record.errors.full_messages.include?(error) }
        end

        def note_params
          params.require(:booking_note).permit(:body)
        end
      end
    end
  end
end
