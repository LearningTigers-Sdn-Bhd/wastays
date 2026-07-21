# frozen_string_literal: true

require "ostruct"

module HotelPortal
  module Bookings
    module Actions
      class CheckInsController < BaseController
        include GroupLifecycleTargeting

        before_action :ensure_eligible!

        def show
          prepare_form
          return create if request.post?

          render :show, layout: false
        end

        private

        def create
          bookings = selected_bookings
          result = ::Bookings::ProcessCheckIn.new(
            bookings: bookings,
            details: submitted_details,
            user: current_user,
            source: params[:source]
          ).call

          if result.success?
            notice = bookings.one? ? success_notice : batch_lifecycle_notice(bookings, @editing_check_in ? "check-in details updated" : "checked in")
            complete_action(notice: notice)
          else
            add_error(result.error)
            render_failure
          end
        rescue BatchTargetError => e
          add_error(e.message)
          render_failure
        end

        def selected_bookings
          action = @editing_check_in ? :edit_check_in : :check_in
          selected_lifecycle_bookings(fallback_booking: @booking, action: action)
        end

        def submitted_details
          source = raw_check_in_params
          details = source.permit(
            :checked_in_at,
            :reason,
            :override_night_audit,
            :tourism_tax_collected,
            :collect_security_deposit,
            security_deposit: [ :amount, :payment_method, :external_reference ]
          ).to_h.deep_symbolize_keys
          details[:room_assignments] = normalize_room_assignments(source[:room_assignments])
          details[:security_deposit] = nil unless ActiveModel::Type::Boolean.new.cast(details.delete(:collect_security_deposit))
          details
        end

        def raw_check_in_params
          value = params[:check_in]
          value.is_a?(ActionController::Parameters) ? value : ActionController::Parameters.new
        end

        def normalize_room_assignments(value)
          return {} unless value.is_a?(Hash) || value.is_a?(ActionController::Parameters)

          value.each_pair.each_with_object({}) do |(booking_room_id, assignment), values|
            values[booking_room_id.to_s] = if assignment.is_a?(Hash) || assignment.is_a?(ActionController::Parameters)
              assignment[:room_number]
            else
              assignment
            end
          end
        end

        def ensure_eligible!
          return if @booking.status.in?(%w[confirmed checked_in])

          redirect_to @return_to, alert: "Check-in is only available for confirmed or checked-in bookings."
        end

        def prepare_form
          @editing_check_in = @booking.checked_in?
          @selected_booking_ids = Array(params[:booking_ids]).reject(&:blank?)
          @target_scope = params[:target_scope].presence || "individual"
          @requires_override = requires_override?
          @form_values = form_values
          @room_options = build_room_options
        end

        def form_values
          submitted = submitted_details
          deposit = submitted[:security_deposit] || {}
          tourism_tax_collected = if submitted.key?(:tourism_tax_collected)
            ActiveModel::Type::Boolean.new.cast(submitted[:tourism_tax_collected])
          else
            @booking.tourism_tax_collected
          end
          {
            checked_in_at: submitted[:checked_in_at].presence || @presenter.checked_in_at_form_value,
            reason: submitted[:reason].to_s,
            override_night_audit: ActiveModel::Type::Boolean.new.cast(submitted[:override_night_audit]),
            collect_security_deposit: submitted[:security_deposit].present?,
            security_deposit_amount: deposit[:amount].presence || "0.00",
            security_deposit_payment_method: deposit[:payment_method].presence || "cash",
            security_deposit_reference: deposit[:external_reference].to_s,
            tourism_tax_collected:,
            room_assignments: submitted[:room_assignments],
            requires_override: @requires_override
          }
        end

        def requires_override?
          return @presenter.requires_backdated_checkin_reason? unless @booking.group_booking_id?

          expected_status = @editing_check_in ? "checked_in" : "confirmed"
          @booking.group_booking.bookings.where(status: expected_status).any? do |booking|
            HotelPortal::BookingPresenter.new(booking, current_hotel).requires_backdated_checkin_reason?
          end
        end

        def build_room_options
          submitted_assignments = @form_values[:room_assignments]
          @booking.booking_rooms.index_with do |booking_room|
            selected = submitted_assignments.key?(booking_room.id.to_s) ? submitted_assignments[booking_room.id.to_s] : booking_room.room_number
            choices = ::Bookings::AvailableRoomNumbers.new(
              hotel: current_hotel,
              room_type: booking_room.room_type,
              check_in: @booking.check_in,
              check_out: @booking.check_out,
              exclude_booking_id: @booking.id
            ).options.map do |option|
              { label: option[:label], value: option[:room_number], disabled: !option[:selectable] }
            end
            { selected: selected.to_s, choices: choices }
          end
        end

        def render_failure
          prepare_form
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: turbo_stream.update(
                requesting_sheet_frame,
                partial: "hotel_portal/bookings/actions/check_ins/form"
              ), status: :unprocessable_content
            end
            format.html { render :show, layout: false, status: :unprocessable_content }
          end
        end

        def add_error(message)
          @booking.errors.add(:base, message)
        end

        def success_notice
          @editing_check_in ? "Check-in details updated." : "Guest checked in successfully."
        end
      end
    end
  end
end
