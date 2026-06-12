# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Show
      module Actions
        class ManageInternalNotesController < BaseController
          MODES = %w[add edit history].freeze

          before_action :set_mode
          before_action :set_note, unless: -> { @mode == "add" }

          def show
            return create_note if request.post? && @mode == "add"
            return update_note if request.patch? && @mode == "edit"
            raise ActiveRecord::RecordNotFound unless request.get?

            @note ||= @booking.booking_notes.build
            render_sheet
          end

          private

          def set_mode
            @mode = params[:mode].presence_in(MODES) || "add"
          end

          def set_note
            @note = @booking.booking_notes.find(params[:note_id])
          end

          def create_note
            @note = @booking.booking_notes.build(note_params)
            @note.user = current_user
            return render_sheet(status: :unprocessable_content) unless @note.save

            record_note_audit("note_added", old_value: {}, new_value: { "body" => @note.body })
            complete_action(notice: "Note added.")
          end

          def update_note
            updated_body = note_params[:body].to_s.strip
            @note.errors.add(:body, "can't be blank") if updated_body.blank?
            return render_sheet(status: :unprocessable_content) if @note.errors.any?

            previous_body = @note.body
            if updated_body != previous_body
              @note.edit_history = Array(@note.edit_history) + [
                { body: previous_body, edited_at: Time.current.iso8601, edited_by_name: current_user.name }
              ]
            end

            return render_sheet(status: :unprocessable_content) unless @note.update(body: updated_body)

            record_note_audit("note_updated", old_value: { "body" => previous_body }, new_value: { "body" => updated_body })
            complete_action(notice: "Note updated.")
          end

          def record_note_audit(action_type, old_value:, new_value:)
            ::Bookings::RecordAuditLog.call(
              auditable: @booking,
              user: current_user,
              action_type: action_type,
              old_value: old_value,
              new_value: new_value,
              metadata: { "note_id" => @note.id }
            )
          end

          def note_params
            params.require(:booking_note).permit(:body)
          end

          def render_sheet(status: :ok)
            render "hotel_portal/bookings/show/actions/manage_internal_notes/offcanvas", status: status
          end
        end
      end
    end
  end
end
