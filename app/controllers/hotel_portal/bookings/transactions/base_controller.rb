# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Transactions
      class BaseController < HotelPortal::BaseController
        include OffcanvasTransactionCompletion
        include GroupLifecycleTargeting

        before_action :authorize_manage_bookings!
        before_action :set_transaction_source
        before_action :set_transaction_return_to

        private

        def set_transaction_source
          @transaction_source = params[:source].presence
        end

        def set_transaction_return_to
          @transaction_return_to = offcanvas_return_to(fallback: request.referer)
        end

        def complete_existing_booking(booking, notice:)
          offcanvas_transaction_response(
            destination: offcanvas_return_to(fallback: hotel_booking_control_panel_path(current_hotel, booking, tab: "booking_details")),
            notice: notice
          )
        end

        def complete_new_booking(booking, notice:)
          scope = booking.group_booking_id? ? "group" : nil
          offcanvas_transaction_response(destination: hotel_booking_control_panel_path(current_hotel, booking, scope: scope), notice: notice)
        end

        def set_booking
          @booking = current_hotel.bookings
                                  .includes(
                                    booking_folio: [ :folio_transactions, :folio_forecasted_charges ],
                                    booking_rooms: [ :room_type, :rate_plan ],
                                    booking_guests: :guest,
                                    booking_notes: :user
                                  )
                                  .find(params[:booking_id])
          @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
        end

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

        def create_manual_booking(source: nil)
          room_type = current_hotel.room_types.find(booking_params[:room_type_id])
          rate_plan, rate_tier = parse_rate_selection(room_type, booking_params[:rate_plan_id])

          ::Bookings::CreateManualBooking.new(
            hotel: current_hotel,
            params: booking_params.merge(
              source: source || booking_params[:source],
              rate_plan_id: rate_plan&.id,
              posting_date: params[:posting_date]
            ),
            user: current_user,
            rate_tier: rate_tier
          ).call
        end

        def render_new_booking(transaction:, status: :ok)
          @transaction = transaction
          @room_types ||= current_hotel.room_types.order(:name)
          @corporate_accounts ||= current_hotel.hotel_corporate_accounts.active.includes(:corporate_account).to_a.sort_by { |relationship| relationship.corporate_account.name.to_s }
          render "hotel_portal/bookings/transactions/new_booking/offcanvas", status: status
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
                turbo_stream.update("offcanvas_drawer", partial: "hotel_portal/bookings/transactions/new_booking/form"),
                turbo_stream.prepend("flash_toasts", partial: "shared/toast", locals: { key: "alert", value: alert })
              ], status: :unprocessable_content
            end
            format.html { render "hotel_portal/bookings/transactions/new_booking/offcanvas", status: :unprocessable_content }
          end
        end

        def create_staff_booking(booking_type: nil)
          ::Bookings::CreateStaffBooking.new(
            hotel: current_hotel, common_params: staff_booking_common_params,
            room_rows: staff_room_rows, user: current_user,
            booking_type: booking_type || params[:booking_type], posting_date: params[:posting_date]
          ).call
        end

        def staff_room_rows
          rows = booking_params[:rooms]
          return rows.values if rows.respond_to?(:values) && !rows.is_a?(Array)
          return rows if rows.present?

          [ booking_params.slice(:room_type_id, :room_number, :rate_plan_id, :adults, :children, :manual_rate_override) ]
        end

        def staff_booking_common_params
          booking_params.except(:rooms, :room_type_id, :room_number, :rate_plan_id, :adults, :children, :manual_rate_override).merge(
            backdate_reason: params[:backdate_reason], retroactive_reason: params[:retroactive_reason]
          )
        end

        def parse_rate_selection(room_type, rate_plan_id)
          return [ nil, :standard ] if rate_plan_id.blank?

          if rate_plan_id.to_s.start_with?("tier_")
            parts = rate_plan_id.to_s.split("_")
            kind = parts[1] == "walk" ? :walk_in : parts[1].to_sym
            [ room_type.rate_plans.find_by(id: parts.last), kind ]
          else
            [ room_type.rate_plans.find_by(id: rate_plan_id), :standard ]
          end
        end

        def booking_params
          params.fetch(:booking, {}).permit(
            :guest_name, :guest_email, :guest_phone, :checked_in_at,
            :guest_country, :guest_gender, :guest_document_type, :guest_government_id, :guest_date_of_birth, :guest_update_intent,
            :room_type_id, :room_number, :check_in, :check_out, :adults, :children, :total_amount,
            :record_payment, :payment_method, :payment_amount, :payment_reference,
            :id_front, :id_back, :source, :internal_notes, :manual_rate_override, :existing_guest_id,
            :rate_plan_id, :apply_stop_sell_restriction, :apply_arrival_departure_restrictions, :apply_stay_length_restrictions,
            :guarantee_method,
            :hotel_corporate_account_id,
            rooms: [ :room_type_id, :room_number, :rate_plan_id, :adults, :children, :manual_rate_override ],
            booking_rooms_attributes: [ :id, :room_type_id, :room_number, :rate_plan_id ]
          )
        end

        def model_booking_params
          booking_params.except(
            :room_type_id, :room_number, :record_payment, :payment_method, :payment_amount, :payment_reference,
            :existing_guest_id, :guest_update_intent, :rate_plan_id,
            :apply_stop_sell_restriction, :apply_arrival_departure_restrictions, :apply_stay_length_restrictions,
            :rooms, :hotel_corporate_account_id
          )
        end

        def authorize_manage_bookings!
          raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
        end
      end
    end
  end
end
