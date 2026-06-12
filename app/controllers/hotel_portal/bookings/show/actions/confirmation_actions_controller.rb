# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Show
      module Actions
        class ConfirmationActionsController < BaseController
          ACTIONS = %w[remove_guest delete_internal_note].freeze

          before_action :set_action_type
          before_action :set_target

          def show
            return destroy_target if request.delete?

            render "hotel_portal/bookings/show/actions/confirmation_action/offcanvas"
          end

          private

          def set_action_type
            @action_type = params[:action_type].presence_in(ACTIONS)
            raise ActiveRecord::RecordNotFound unless @action_type
          end

          def set_target
            if @action_type == "remove_guest"
              @booking_guest = @booking.booking_guests.find_by!(id: params[:target_id], is_primary: false)
            else
              @note = @booking.booking_notes.find(params[:target_id])
            end
          end

          def destroy_target
            if @action_type == "remove_guest"
              guest = @booking_guest.guest
              @booking_guest.destroy!
              guest.destroy! if guest.booking_guests.empty?
              complete_action(notice: "Guest removed.")
            else
              deleted_body = @note.body
              deleted_note_id = @note.id
              @note.destroy!
              ::Bookings::RecordAuditLog.call(
                auditable: @booking,
                user: current_user,
                action_type: "note_deleted",
                old_value: { "body" => deleted_body },
                new_value: {},
                metadata: { "note_id" => deleted_note_id }
              )
              complete_action(notice: "Note deleted.")
            end
          end
        end
      end
    end
  end
end
