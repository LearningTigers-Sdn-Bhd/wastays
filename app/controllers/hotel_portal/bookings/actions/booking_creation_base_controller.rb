# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      # Base for Sheet-based booking-creation workflows (new / quick / backdated).
      #
      # Creation has no :booking_id, so it does not use Actions::BaseController.
      # Business rules stay in Bookings::CreateStaffBooking; this only builds the
      # form, orchestrates the service, and renders/complete into the
      # booking_action_sheet frame.
      class BookingCreationBaseController < HotelPortal::BaseController
        include BookingActionCompletion

        before_action :authorize_manage_bookings!

        private

        def build_booking(source: nil)
          incoming = booking_params
          check_in = incoming[:check_in].presence || params[:check_in].presence || ::Bookings::ScheduledStay.at_hotel_time(hotel: current_hotel, value: Date.current, kind: :check_in)
          @booking = current_hotel.bookings.build(
            check_in: check_in,
            check_out: incoming[:check_out].presence || params[:check_out].presence || ::Bookings::ScheduledStay.at_hotel_time(hotel: current_hotel, value: check_in.to_date + 1.day, kind: :check_out),
            adults: 2, source: source
          )
          @booking.assign_attributes(model_booking_params.compact_blank) if params[:booking].present?
          @initial_room_rows = params[:booking].present? ? staff_room_rows.map(&:to_h) : [ {} ]
          @room_type_id = params[:room_type_id]
          @room_number = params[:room_number]
          @room_types = current_hotel.room_types.order(:name)
        end

        def create_staff_booking(booking_type: nil)
          ::Bookings::CreateStaffBooking.new(
            hotel: current_hotel, common_params: staff_booking_common_params,
            room_rows: staff_room_rows, user: current_user,
            booking_type: booking_type || booking_params[:booking_type], posting_date: params[:posting_date]
          ).call
        end

        def complete_new_booking(booking, notice:)
          scope = booking.group_booking_id? ? "group" : nil
          complete_booking_action(destination: hotel_booking_control_panel_path(current_hotel, booking, scope: scope), notice: notice)
        end

        def render_new_booking(transaction:, status: :ok)
          @transaction = transaction
          @room_types ||= current_hotel.room_types.order(:name)
          @corporate_accounts ||= current_hotel.hotel_corporate_accounts.active.includes(:corporate_account).to_a.sort_by { |relationship| relationship.corporate_account.name.to_s }
          render template: "hotel_portal/bookings/actions/booking_creations/show", layout: false, status: status
        end

        def render_new_booking_failure(transaction:, errors:)
          alert = Array(errors).to_sentence.presence || "Booking could not be created."
          @booking = current_hotel.bookings.build(model_booking_params)
          @initial_room_rows = staff_room_rows.map(&:to_h)
          @booking.errors.add(:base, alert)
          @transaction = transaction
          @room_types ||= current_hotel.room_types.order(:name)
          @corporate_accounts ||= current_hotel.hotel_corporate_accounts.active.includes(:corporate_account).to_a.sort_by { |relationship| relationship.corporate_account.name.to_s }
          flash.now[:alert] = alert

          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: [
                turbo_stream.update("booking_action_sheet", partial: "hotel_portal/bookings/actions/booking_creations/form"),
                toast_stream(alert, type: :error)
              ], status: :unprocessable_content
            end
            format.html { render template: "hotel_portal/bookings/actions/booking_creations/show", layout: false, status: :unprocessable_content }
          end
        end

        def staff_room_rows
          rows = booking_params[:rooms]
          return rows.values if rows.respond_to?(:values) && !rows.is_a?(Array)
          return rows if rows.present?

          [ booking_params.slice(:room_type_id, :room_number, :rate_plan_id, :adults, :children, :manual_rate_override) ]
        end

        def staff_booking_common_params
          booking_params.except(:rooms, :room_type_id, :room_number, :rate_plan_id, :adults, :children, :manual_rate_override, :booking_type).merge(
            backdate_reason: booking_params[:backdate_reason].presence || params[:backdate_reason],
            retroactive_reason: params[:retroactive_reason]
          )
        end

        def booking_params
          params.fetch(:booking, {}).permit(
            :guest_name, :guest_email, :guest_phone, :checked_in_at,
            :guest_country, :guest_gender, :guest_document_type, :guest_government_id, :guest_date_of_birth, :guest_update_intent,
            :room_type_id, :room_number, :check_in, :check_out, :adults, :children, :total_amount,
            :record_payment, :payment_method, :payment_amount, :payment_reference,
            :id_front, :id_back, :source, :internal_notes, :manual_rate_override, :existing_guest_id,
            :rate_plan_id, :apply_stop_sell_restriction, :apply_arrival_departure_restrictions, :apply_stay_length_restrictions,
            :guarantee_method, :booking_type, :backdate_reason,
            :hotel_corporate_account_id, :bill_tourism_tax_to_company,
            rooms: [ :room_type_id, :room_number, :rate_plan_id, :adults, :children, :manual_rate_override ],
            booking_rooms_attributes: [ :id, :room_type_id, :room_number, :rate_plan_id ]
          )
        end

        def model_booking_params
          booking_params.except(
            :room_type_id, :room_number, :record_payment, :payment_method, :payment_amount, :payment_reference,
            :existing_guest_id, :guest_update_intent, :rate_plan_id,
            :apply_stop_sell_restriction, :apply_arrival_departure_restrictions, :apply_stay_length_restrictions,
            :rooms, :hotel_corporate_account_id, :bill_tourism_tax_to_company, :booking_type, :backdate_reason
          )
        end

        def authorize_manage_bookings!
          raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
        end
      end
    end
  end
end
