# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Show
      module Actions
        class ManageGuestsController < BaseController
          MODES = %w[add edit_primary edit_additional].freeze

          before_action :set_mode
          before_action :set_primary_booking_guest, if: -> { @mode == "edit_primary" }
          before_action :set_additional_booking_guest, if: -> { @mode == "edit_additional" }

          def show
            return create_additional if request.post? && @mode == "add"
            return update_guest if request.patch? && @mode != "add"
            raise ActiveRecord::RecordNotFound unless request.get? || request.head?

            prepare_guest
            render_sheet
          end

          private

          def set_mode
            @mode = params[:mode].presence_in(MODES) || "add"
          end

          def set_additional_booking_guest
            @booking_guest = @booking.booking_guests.find_by!(id: params[:booking_guest_id], is_primary: false)
          end

          def set_primary_booking_guest
            @booking_guest = @booking.booking_guests.find(&:primary?)
          end

          def prepare_guest
            @guest = if @mode == "edit_additional"
              @booking_guest.guest
            elsif @mode == "edit_primary"
              primary_guest_record
            else
              Guest.new(country: current_hotel.country.presence || "Malaysia", document_type: "ic")
            end
          end

          def create_additional
            @guest = Guest.new(guest_params)
            @guest.created_by_hotel = current_hotel
            if @guest.valid?
              ActiveRecord::Base.transaction do
                @guest.save!
                @booking.booking_guests.create!(guest: @guest, is_primary: false)
                record_guest_audit("guest_added", old_value: {}, new_value: guest_audit_values(@guest))
              end
              return complete_guest_action(notice: "Guest added.")
            end

            render_guest_errors
          end

          def update_guest
            return update_primary_without_snapshot unless @booking_guest

            @guest = @booking_guest.guest
            update_profile = save_scope == "snapshot_and_profile"
            result = ::BookingGuests::UpdateSnapshot.call(
              booking_guest: @booking_guest,
              attributes: guest_params,
              actor: current_user,
              update_profile:,
              bibo_attributes: booking_guest_bibo_params
            )
            return complete_guest_action(notice: update_profile ? "Guest details and guest record updated." : "Guest details saved.") if result.success?

            result.errors.each { |error| @guest.errors.add(:base, error) }
            render_guest_errors
          end

          def update_primary_without_snapshot
            @guest = primary_guest_record
            @guest.assign_attributes(guest_params)
            return render_guest_errors unless @guest.valid?

            result = nil
            success = true
            ActiveRecord::Base.transaction do
              result = ::Bookings::UpdateStayService.new(
                booking: @booking,
                params: primary_booking_params,
                user: current_user
              ).call
              raise ActiveRecord::Rollback unless result.success?

              @booking.reload.primary_guest&.update!(guest_params)
              primary_booking_guest = @booking.booking_guests.find_by(is_primary: true)
              success = apply_booking_guest_bibo!(primary_booking_guest)
              raise ActiveRecord::Rollback unless success
            end

            return complete_guest_action(notice: "Primary guest updated.") if result&.success?

            result.errors.each { |error| @guest.errors.add(:base, error) }
            render_guest_errors
          end

          def primary_guest_record
            @primary_guest_record ||= @booking.primary_guest || Guest.new(
              name: @booking.guest_name,
              email: @booking.guest_email,
              phone: @booking.guest_phone,
              country: @booking.guest_country,
              gender: @booking.guest_gender,
              document_type: @booking.guest_document_type,
              government_id: @booking.guest_government_id,
              date_of_birth: @booking.primary_guest&.date_of_birth
            )
          end

          def save_scope
            requested = params[:save_scope].presence_in(%w[snapshot snapshot_and_profile])
            requested || (inline_request? ? "snapshot" : "snapshot_and_profile")
          end

          def primary_booking_params
            {
              guest_name: guest_params[:name],
              guest_email: guest_params[:email],
              guest_phone: guest_params[:phone],
              guest_country: guest_params[:country],
              guest_gender: guest_params[:gender],
              guest_document_type: guest_params[:document_type],
              guest_government_id: guest_params[:government_id],
              guest_date_of_birth: guest_params[:date_of_birth]
            }
          end

          def booking_guest_bibo_params
            return ActionController::Parameters.new.permit(:boat_in_at, :boat_out_at) unless inline_request?

            params.fetch(:booking_guest, ActionController::Parameters.new).permit(:boat_in_at, :boat_out_at)
          end

          def apply_booking_guest_bibo!(booking_guest)
            return true if booking_guest.blank?

            booking_guest.update(booking_guest_bibo_params)
          end

          def guest_params
            params.require(:guest).permit(:name, :email, :phone, :country, :gender, :document_type, :government_id, :date_of_birth)
          end

          def guest_audit_values(guest)
            guest.attributes.slice("name", "email", "phone", "country", "gender", "document_type", "date_of_birth")
          end

          def record_guest_audit(action_type, old_value:, new_value:)
            ::Bookings::RecordAuditLog.call!(
              auditable: @booking,
              user: current_user,
              action_type: action_type,
              old_value: old_value,
              new_value: new_value
            )
          end

          def render_sheet(status: :ok)
            render "hotel_portal/bookings/show/actions/manage_guest/offcanvas", status: status
          end

          def inline_request?
            params[:presentation] == "booking_control_panel"
          end

          def complete_guest_action(notice:)
            return redirect_to(@return_to, notice: notice, status: :see_other) if inline_request?

            complete_action(notice: notice)
          end

          def render_guest_errors
            return redirect_to(@return_to, alert: @guest.errors.full_messages.to_sentence, status: :see_other) if inline_request?

            render_sheet(status: :unprocessable_content)
          end
        end
      end
    end
  end
end
