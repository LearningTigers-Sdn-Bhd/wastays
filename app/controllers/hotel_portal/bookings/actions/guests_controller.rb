# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      class GuestsController < BaseController
        MODES = %w[add edit_primary edit_additional].freeze

        before_action :set_mode, only: :show
        before_action :set_booking_guest, if: -> { action_name == "show" && @mode != "add" }
        before_action :set_removal_guest, only: :remove
        before_action :set_primary_candidate, only: :set_primary

        def show
          return create if request.post? && @mode == "add"
          return update if request.patch? && @mode != "add"
          raise ActiveRecord::RecordNotFound unless request.get? && @mode == "add"

          @guest = Guest.new(country: current_hotel.country.presence || "Malaysia", document_type: "ic")
          render :show, layout: false
        end

        def remove
          return destroy if request.delete?

          render :remove, layout: false
        end

        def set_primary
          result = ::Bookings::SetPrimaryGuest.call(booking: @booking, booking_guest: @booking_guest, actor: current_user)
          @return_to = hotel_booking_workspace_path(current_hotel, @booking, tab: "guest_details", booking_guest_id: @booking_guest.id)
          result.success? ? complete_action(notice: "Primary guest updated.") : complete_action(alert: result.error)
        end

        private

        def set_mode
          @mode = params[:mode].presence_in(MODES)
          @mode = "add" if params[:mode].blank?
          raise ActiveRecord::RecordNotFound unless @mode
        end

        def set_booking_guest
          @booking_guest = if @mode == "edit_primary"
            @booking.booking_guests.find(&:primary?)
          else
            @booking.booking_guests.find_by!(id: params[:booking_guest_id], is_primary: false)
          end
        end

        def set_removal_guest
          @booking_guest = @booking.booking_guests.find_by!(id: params[:booking_guest_id], is_primary: false)
        end

        def set_primary_candidate
          @booking_guest = @booking.booking_guests.find(params[:booking_guest_id])
        end

        def set_return_to
          fallback = hotel_booking_workspace_path(
            current_hotel,
            @booking,
            tab: "guest_details",
            booking_guest_id: params[:booking_guest_id].presence
          )
          @return_to = booking_action_return_to(fallback:)
        end

        def create
          target = resolved_guest_target
          if target == :group && params[:confirm_group] != "1"
            @guest = Guest.new(guest_params)
            @review_group = true
            return render_guest_review
          end

          result = if target == :group
            ::BookingGuests::AddToGroup.call(group_booking: @booking.group_booking, attributes: guest_params, actor: current_user)
          else
            ::BookingGuests::Add.call(booking: target, attributes: guest_params, actor: current_user)
          end
          @guest = result.guest
          return complete_action(notice: "Guest added.") if result.success?

          add_errors(@guest, result.errors)
          render_guest_failure
        end

        # Boat slots are picked in the guest details panel and the check-in
        # flows, never in this sheet, so nothing here touches them.
        def update
          result = if @booking_guest
            ::BookingGuests::UpdateSnapshot.call(
              booking_guest: @booking_guest,
              attributes: guest_params,
              actor: current_user,
              update_profile: save_scope == "snapshot_and_profile"
            )
          else
            ::BookingGuests::UpdatePrimary.call(
              booking: @booking,
              attributes: guest_params,
              actor: current_user
            )
          end

          if result.success?
            notice = save_scope == "snapshot_and_profile" ? "Guest details and guest record updated." : "Guest details saved."
            redirect_to @return_to, notice:, status: :see_other
          else
            redirect_to @return_to, alert: result.errors.to_sentence, status: :see_other
          end
        end

        def destroy
          result = ::BookingGuests::Remove.call(booking_guest: @booking_guest, actor: current_user)
          result.success? ? complete_action(notice: "Guest removed.") : complete_action(alert: result.error)
        end

        def render_guest_failure
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: turbo_stream.update(
                requesting_sheet_frame,
                partial: "hotel_portal/bookings/actions/guests/form"
              ), status: :unprocessable_content
            end
            format.html { render :show, layout: false, status: :unprocessable_content }
          end
        end

        def render_guest_review
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: turbo_stream.update(
                requesting_sheet_frame,
                partial: "hotel_portal/bookings/actions/guests/form"
              )
            end
            format.html { render :show, layout: false }
          end
        end

        def add_errors(record, errors)
          errors.each { |error| record.errors.add(:base, error) unless record.errors.full_messages.include?(error) }
        end

        def save_scope
          params[:save_scope].presence_in(%w[snapshot snapshot_and_profile]) || "snapshot"
        end

        def guest_params
          params.require(:guest).permit(:name, :email, :phone, :country, :gender, :document_type, :government_id, :date_of_birth, :home_address)
        end

        def resolved_guest_target
          value = params.dig(:guest, :apply_to).presence
          return @booking if @booking.group_booking_id.blank?
          return :group if value == "group"

          id = value.to_s.delete_prefix("booking:")
          @booking.group_booking.bookings.where(hotel_id: current_hotel.id).find(id)
        end
      end
    end
  end
end
