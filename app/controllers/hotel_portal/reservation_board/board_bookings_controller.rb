# frozen_string_literal: true

module HotelPortal
  module ReservationBoard
    class BoardBookingsController < BaseController
      before_action :authorize_manage_bookings!

      def new
        check_in = params[:check_in].presence || Date.current
        @booking = current_hotel.bookings.build(
          check_in: check_in,
          check_out: params[:check_out].presence || (Date.parse(check_in.to_s) + 2.days),
          adults: 2
        )

        # Pre-select room type if provided
        @room_type_id = params[:room_type_id]
        @room_number = params[:room_number]

        # Calculate initial price if room type is provided
        if @room_type_id.present?
          room_type = current_hotel.room_types.find(@room_type_id)
          snapshot = ::Bookings::BuildFinancialSnapshot.new(
            hotel: current_hotel,
            room_type: room_type,
            check_in: @booking.check_in,
            check_out: @booking.check_out,
            guest_country: current_hotel.country
          ).call
          @booking.total_amount = snapshot.room_total + snapshot.tax_total
        end

        @room_types = current_hotel.room_types.order(:name)
        render :new
      end

      def show
        @booking = current_hotel.bookings
                                .includes(
                                  booking_folio: [ :folio_transactions, :folio_forecasted_charges ],
                                  booking_rooms: [ :room_type, :rate_plan ],
                                  booking_guests: :guest,
                                  booking_notes: :user
                                )
                                .find(params[:id])
        set_show_breadcrumbs
        @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
        set_audit_logs
        render :show_page
      end

      def booking_sheet
        @booking = current_hotel.bookings.includes(booking_rooms: :room_type).find(params[:id])
        @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
        @room_types = current_hotel.room_types.order(:name)
        @notes = @booking.booking_notes.includes(:user).order(created_at: :desc)
      end

      def check_in
        @booking = current_hotel.bookings.includes(booking_rooms: :room_type).find(params[:id])
        @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
      end

      def check_out
        @booking = current_hotel.bookings.includes(booking_folio: { folio_transactions: :user }).find(params[:id])
        @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
      end

      def edit_stay
        @booking = current_hotel.bookings.find(params[:id])
        @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
        @room_types = current_hotel.room_types.order(:name)
      end

      def notes
        @booking = current_hotel.bookings.find(params[:id])
        @notes = @booking.booking_notes.includes(:user).order(created_at: :desc)
      end

      def late_checkout
        @booking = current_hotel.bookings.find(params[:id])
        @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
      end

      def folio
        @booking = current_hotel.bookings.includes(booking_folio: [ { folio_transactions: :user }, :folio_forecasted_charges ]).find(params[:id])
        set_folio_breadcrumbs
        @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
      end

      def update
        @booking = current_hotel.bookings.find(params[:id])
        result = ::Bookings::UpdateStayService.new(
          booking: @booking,
          params: booking_params,
          user: current_user
        ).call

        if result.success?
          respond_to do |format|
            format.turbo_stream do
              @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
              set_audit_logs
              render turbo_stream: [
                turbo_stream.action(:reload, "reservation_board"),
                turbo_stream.append("reservation_board", partial: "shared/toast", locals: { key: "notice", value: "Booking updated successfully." })
              ]
            end
            format.html { redirect_to hotel_reservation_board_index_path(current_hotel), notice: "Booking updated." }
          end
        else
          @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
          @room_types = current_hotel.room_types.order(:name)
          @booking.errors.add(:base, result.errors.to_sentence)
          render :edit_stay, status: :unprocessable_content
        end
      end

      def create
        room_type = current_hotel.room_types.find(booking_params[:room_type_id])
        rate_plan, rate_tier = parse_rate_selection(room_type, booking_params[:rate_plan_id])

        result = ::Bookings::CreateManualBooking.new(
          hotel: current_hotel,
          params: booking_params.merge(rate_plan_id: rate_plan&.id),
          user: current_user,
          rate_tier: rate_tier
        ).call

        if result.success?
          respond_to do |format|
            format.turbo_stream do
              render turbo_stream: [
                turbo_stream.action(:reload, "reservation_board"),
                turbo_stream.append("reservation_board", partial: "shared/toast", locals: { key: "notice", value: "Booking created successfully." })
              ]
            end
            format.html { redirect_to hotel_reservation_board_index_path(current_hotel), notice: "Booking created successfully." }
          end
        else
          @booking = current_hotel.bookings.build(booking_params.except(*manual_booking_form_only_param_keys))
          @room_types = current_hotel.room_types.order(:name)
          flash.now[:alert] = result.errors.to_sentence
          render :new, status: :unprocessable_content
        end
      end

      def transition
        @booking = current_hotel.bookings.find(params[:id])
        result = ::Bookings::TransitionStatus.new(
          booking: @booking,
          status: params[:status],
          user: current_user
        ).call

        if result.success?
          respond_to do |format|
            format.turbo_stream { render turbo_stream: turbo_stream.action(:reload, "reservation_board") }
            format.html { redirect_to hotel_reservation_board_index_path(current_hotel), notice: "Booking status updated." }
          end
        else
          respond_to do |format|
            format.turbo_stream { render turbo_stream: turbo_stream.append("reservation_board", partial: "shared/toast", locals: { key: "alert", value: result.error }) }
            format.html { redirect_to hotel_reservation_board_index_path(current_hotel), alert: result.error }
          end
        end
      end

      private

      def set_show_breadcrumbs
        override_breadcrumbs(
          { label: "Operations" },
          { label: "Reservation Board", path: hotel_reservation_board_index_path(current_hotel) },
          { label: @booking.confirmation_token }
        )
      end

      def set_folio_breadcrumbs
        override_breadcrumbs(
          { label: "Operations" },
          { label: "Reservation Board", path: hotel_reservation_board_index_path(current_hotel) },
          { label: @booking.confirmation_token, path: hotel_reservation_board_board_booking_path(current_hotel, @booking) },
          { label: "Folio Ledger" }
        )
      end

      def set_audit_logs
        # Fetch audit logs for this booking and its related entities
        base_query = BookingAuditLog.where(hotel: current_hotel)

        @audit_logs = base_query.where(auditable: @booking)

        if @booking.booking_quote_id.present?
          @audit_logs = @audit_logs.or(base_query.where(auditable_type: "BookingQuote", auditable_id: @booking.booking_quote_id))
        end

        @audit_logs = @audit_logs.or(base_query.where(auditable_type: "BookingRoom", auditable_id: @booking.booking_rooms.select(:id)))
                                .includes(:user, :auditable)
                                .order(created_at: :desc)
      end

      def booking_params
        params.fetch(:booking, {}).permit(
          :guest_name, :guest_email, :guest_phone, :status,
          :guest_country, :guest_gender, :guest_document_type, :guest_government_id, :guest_update_intent,
          :room_type_id, :room_number, :check_in, :check_out, :adults, :children, :total_amount,
          :record_payment, :payment_method, :payment_amount, :payment_reference,
          :id_front, :id_back, :source, :internal_notes, :manual_rate_override, :existing_guest_id,
          :rate_plan_id, :apply_stop_sell_restriction, :apply_arrival_departure_restrictions, :apply_stay_length_restrictions,
          :guarantee_method,
          booking_rooms_attributes: [ :id, :room_type_id, :room_number, :rate_plan_id ]
        )
      end

      def parse_rate_selection(room_type, rate_plan_id)
        return [ nil, :standard ] if rate_plan_id.blank?

        if rate_plan_id.to_s.start_with?("tier_")
          parts = rate_plan_id.to_s.split("_")
          kind = parts[1] == "walk" ? :walk_in : parts[1].to_sym
          real_plan_id = parts.last
          plan = room_type.rate_plans.find_by(id: real_plan_id)
          [ plan, kind ]
        else
          plan = room_type.rate_plans.find_by(id: rate_plan_id)
          [ plan, :standard ]
        end
      end

      def manual_booking_form_only_param_keys
        %i[
          room_type_id room_number record_payment payment_method payment_amount payment_reference
          existing_guest_id guest_update_intent rate_plan_id
          apply_stop_sell_restriction apply_arrival_departure_restrictions apply_stay_length_restrictions
        ]
      end

      def authorize_manage_bookings!
        raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
      end
    end
  end
end
