# frozen_string_literal: true

class HotelPortal::BookingsController < HotelPortal::BaseController
  include BookingAuditable

  before_action :authorize_view_bookings!, only: %i[index show]
  before_action :authorize_manage_bookings!, only: %i[new create update]

  def index
    @all_bookings = current_hotel.bookings.recent_first.includes(:booking_folio)
    @all_bookings = @all_bookings.search(params[:query]) if params[:query].present?
    @all_bookings = @all_bookings.where(status: params[:status]) if params[:status].present?

    @bookings = @all_bookings.page(params[:page]).per(25)
  end

  def new
    unless turbo_frame_request?
      redirect_to hotel_bookings_path(current_hotel)
      return
    end

    @booking = current_hotel.bookings.build(
      check_in: params[:check_in].presence || Date.current,
      check_out: params[:check_out].presence || Date.current + 1.day,
      adults: 2
    )

    if params[:room_type_id].present?
      room_type = current_hotel.room_types.find(params[:room_type_id])
      snapshot = Bookings::BuildFinancialSnapshot.new(
        hotel: current_hotel,
        room_type: room_type,
        check_in: @booking.check_in,
        check_out: @booking.check_out,
        guest_country: current_hotel.country
      ).call
      @booking.total_amount = snapshot.room_total + snapshot.tax_total
    end

    @room_types = current_hotel.room_types.order(:name)
  end

  def create
    room_type = current_hotel.room_types.find(booking_params[:room_type_id])
    rate_plan, rate_tier = parse_rate_selection(room_type, booking_params[:rate_plan_id])

    result = Bookings::CreateManualBooking.new(
      hotel: current_hotel,
      params: booking_params.merge(rate_plan_id: rate_plan&.id),
      user: current_user,
      rate_tier: rate_tier
    ).call

    if result.success?
      release_room_locks(result.booking)

      respond_to do |format|
        format.turbo_stream do
          flash[:notice] = "Booking created successfully."
          render turbo_stream: turbo_stream_redirect_to(hotel_booking_path(current_hotel, result.booking))
        end
        format.html { redirect_to hotel_booking_path(current_hotel, result.booking), notice: "Booking created successfully." }
      end
    else
      Rails.logger.error "ManualBooking Creation Failed: #{result.errors.join(", ")}"
      @booking = current_hotel.bookings.build(booking_params.except(*manual_booking_form_only_param_keys))
      result.errors.each { |error| @booking.errors.add(:base, error) }
      @room_types = current_hotel.room_types.order(:name)
      flash.now[:alert] = result.errors.to_sentence

      respond_to do |format|
        format.turbo_stream { render :new, formats: [ :html ], layout: false, status: :unprocessable_content }
        format.html { render :new, status: :unprocessable_content }
      end
    end
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
    set_breadcrumbs
    @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
    set_audit_logs(@booking)
  end

  def update
    @booking = current_hotel.bookings.find(params[:id])
    result = Bookings::UpdateStayService.new(
      booking: @booking,
      params: booking_params,
      user: current_user,
      override: params[:override_room_status],
      override_reason: params[:override_room_status_reason]
    ).call

    if result.success?
      release_room_locks(@booking)
      respond_to do |format|
        format.html { redirect_to hotel_booking_path(current_hotel, @booking), notice: "Booking updated successfully." }
        format.json { render json: { success: true, booking: @booking } }
      end
    else
      respond_to do |format|
        format.html do
          @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
          set_breadcrumbs
          set_audit_logs(@booking)
          @booking.errors.add(:base, result.errors.to_sentence)
          render :show, status: :unprocessable_content
        end
        format.json { render json: { success: false, errors: result.errors }, status: :unprocessable_content }
      end
    end
  end

  private

  def release_room_locks(booking)
    room_number = booking.hotel_snapshot.is_a?(Hash) ? (booking.hotel_snapshot["room_number"] || booking.hotel_snapshot.dig("assignment", "room_number")) : nil
    RoomLock.where(hotel: current_hotel, user: current_user, room_number: room_number).destroy_all if room_number.present?
  end

  def set_breadcrumbs
    override_breadcrumbs(
      { label: "Operations" },
      { label: "Bookings", path: hotel_bookings_path(current_hotel) },
      { label: @booking.confirmation_token }
    )
  end

  def booking_params
    params.fetch(:booking, {}).permit(
      :guest_name, :guest_email, :guest_phone, :checked_in_at, :checked_out_at,
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

  def turbo_stream_redirect_to(path)
    %(<turbo-stream action="redirect" url="#{ERB::Util.html_escape(path)}"></turbo-stream>).html_safe
  end

  def authorize_view_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_bookings", hotel: current_hotel)
  end

  def authorize_manage_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
  end
end
